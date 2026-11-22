#!/bin/bash

# Script de verification du serveur Pixelia
# A lancer avec sudo depuis le dossier du projet

nombre_tests=0
tests_reussis=0

# Verifier que le script est lance avec sudo
if [ "$EUID" -ne 0 ]; then
    echo "Il faut lancer ce script avec sudo"
    exit 1
fi

if [ ! -f comptes.csv ]; then
    echo "Lancez le script depuis le dossier du projet"
    exit 1
fi

# Fonctions pour afficher les resultats
ok() {
    echo "[OK] $1 : $2"
    nombre_tests=$((nombre_tests + 1))
    tests_reussis=$((tests_reussis + 1))
}

ko() {
    echo "[KO] $1 : $2"
    nombre_tests=$((nombre_tests + 1))
}


# C1 : comptes et groupes
# Fichiers a verifier : comptes.csv et creer_comptes.sh
test_C1() {

    # Verifier les groupes
    for groupe in admins acces_ssh support dev design commercial freelance
    do
        if getent group "$groupe" > /dev/null; then
            ok "C1" "Le groupe $groupe existe"
        else
            ko "C1" "Le groupe $groupe n'existe pas"
        fi
    done

    # Verifier les utilisateurs du fichier comptes.csv
    while IFS=";" read -r utilisateur nom groupe autres
    do
        if [ "$utilisateur" != "login" ]; then

            if id "$utilisateur" > /dev/null 2>&1; then
                ok "C1" "Le compte $utilisateur existe"

                if [ "$(id -gn "$utilisateur")" = "$groupe" ]; then
                    ok "C1" "$utilisateur est dans le bon groupe principal"
                else
                    ko "C1" "$utilisateur n'a pas le bon groupe principal"
                fi

                # Verifier les groupes secondaires
                for autre_groupe in $(echo "$autres" | tr ',' ' ')
                do
                    if id -nG "$utilisateur" | grep -qw "$autre_groupe"; then
                        ok "C1" "$utilisateur est dans $autre_groupe"
                    else
                        ko "C1" "$utilisateur n'est pas dans $autre_groupe"
                    fi
                done

            else
                ko "C1" "Le compte $utilisateur n'existe pas"
            fi

        fi
    done < comptes.csv

    # Verifier l'expiration des freelances
    for utilisateur in freelance1 freelance2
    do
        expiration=$(getent shadow "$utilisateur" | cut -d: -f8)

        if [ -n "$expiration" ]; then
            ok "C1" "$utilisateur a une date d'expiration"
        else
            ko "C1" "$utilisateur n'a pas de date d'expiration"
        fi
    done
}


# C2 : droits sur les dossiers
# Fichier a verifier : creer_comptes.sh
# Dossiers concernes : /srv/projets, /srv/maquettes, /srv/clients

test_C2() {

    if sudo -u dev1 test -w /srv/projets; then
        ok "C2" "dev1 peut ecrire dans /srv/projets"
    else
        ko "C2" "dev1 ne peut pas ecrire dans /srv/projets"
    fi

    if sudo -u design1 test -r /srv/projets; then
        ok "C2" "design1 peut lire /srv/projets"
    else
        ko "C2" "design1 ne peut pas lire /srv/projets"
    fi

    if sudo -u design1 test -w /srv/projets; then
        ko "C2" "design1 peut ecrire dans /srv/projets"
    else
        ok "C2" "design1 ne peut pas ecrire dans /srv/projets"
    fi

    if sudo -u commercial1 test -r /srv/projets; then
        ko "C2" "commercial1 peut lire /srv/projets"
    else
        ok "C2" "commercial1 ne peut pas lire /srv/projets"
    fi

    if sudo -u freelance1 test -w /srv/projets/externe; then
        ok "C2" "freelance1 peut ecrire dans /srv/projets/externe"
    else
        ko "C2" "freelance1 ne peut pas ecrire dans /srv/projets/externe"
    fi

    if sudo -u freelance1 test -r /srv/projets; then
        ko "C2" "freelance1 peut lire /srv/projets"
    else
        ok "C2" "freelance1 ne peut pas lire /srv/projets"
    fi

    if sudo -u design1 test -w /srv/maquettes; then
        ok "C2" "design1 peut ecrire dans /srv/maquettes"
    else
        ko "C2" "design1 ne peut pas ecrire dans /srv/maquettes"
    fi

    if sudo -u dev1 test -r /srv/maquettes; then
        ok "C2" "dev1 peut lire /srv/maquettes"
    else
        ko "C2" "dev1 ne peut pas lire /srv/maquettes"
    fi

    if sudo -u dev1 test -w /srv/maquettes; then
        ko "C2" "dev1 peut ecrire dans /srv/maquettes"
    else
        ok "C2" "dev1 ne peut pas ecrire dans /srv/maquettes"
    fi

    if sudo -u commercial1 test -w /srv/clients; then
        ok "C2" "commercial1 peut ecrire dans /srv/clients"
    else
        ko "C2" "commercial1 ne peut pas ecrire dans /srv/clients"
    fi

    if sudo -u dev1 test -r /srv/clients; then
        ko "C2" "dev1 peut lire /srv/clients"
    else
        ok "C2" "dev1 ne peut pas lire /srv/clients"
    fi

    # Verifier les ACL par defaut
    if getfacl /srv/projets 2> /dev/null | grep -q "default:group:dev:rwx"; then
        ok "C2" "ACL par defaut sur /srv/projets"
    else
        ko "C2" "ACL par defaut absente sur /srv/projets"
    fi

    if getfacl /srv/projets/externe 2> /dev/null | grep -q "default:group:freelance:rwx"; then
        ok "C2" "ACL par defaut sur /srv/projets/externe"
    else
        ko "C2" "ACL par defaut absente sur /srv/projets/externe"
    fi

    if getfacl /srv/maquettes 2> /dev/null | grep -q "default:group:design:rwx"; then
        ok "C2" "ACL par defaut sur /srv/maquettes"
    else
        ko "C2" "ACL par defaut absente sur /srv/maquettes"
    fi

    if getfacl /srv/clients 2> /dev/null | grep -q "default:group:commercial:rwx"; then
        ok "C2" "ACL par defaut sur /srv/clients"
    else
        ko "C2" "ACL par defaut absente sur /srv/clients"
    fi
}


# C3 : droits sudo
# Fichiers a verifier : config/sudoers.d/ et installer.sh
test_C3() {

    # Verifier les administrateurs
    for utilisateur in nicolas leo
    do
        if sudo -l -U "$utilisateur" | grep -q "(ALL : ALL) ALL"; then
            ok "C3" "$utilisateur a les droits sudo"
        else
            ko "C3" "$utilisateur n'a pas les droits sudo"
        fi
    done

    # Verifier le compte support
    if sudo -l -U support | grep -q "/usr/local/sbin/analyse_logs.sh"; then
        ok "C3" "support peut lancer analyse_logs.sh"
    else
        ko "C3" "support ne peut pas lancer analyse_logs.sh"
    fi

    if sudo -l -U support | grep -q "(ALL : ALL) ALL"; then
        ko "C3" "support a tous les droits sudo"
    else
        ok "C3" "support n'a pas tous les droits sudo"
    fi

    # Verifier les comptes metier
    for utilisateur in dev1 dev2 design1 design2 commercial1 commercial2 freelance1 freelance2
    do
        if id -nG "$utilisateur" | grep -qw "sudo"; then
            ko "C3" "$utilisateur est dans le groupe sudo"
        else
            ok "C3" "$utilisateur n'est pas dans le groupe sudo"
        fi

        if id -nG "$utilisateur" | grep -qw "admins"; then
            ko "C3" "$utilisateur est dans le groupe admins"
        else
            ok "C3" "$utilisateur n'est pas dans le groupe admins"
        fi

        # sudo -l lit les vraies regles sudo : il trouve aussi une regle
        # ajoutee directement pour l'utilisateur dans /etc/sudoers.d/
        if sudo -l -U "$utilisateur" | grep -q "ALL"; then
            ko "C3" "$utilisateur a des droits sudo"
        else
            ok "C3" "$utilisateur n'a aucun droit sudo"
        fi
    done

    # Le groupe sudo doit etre vide
    membres=$(getent group sudo | cut -d: -f4)

    if [ -z "$membres" ]; then
        ok "C3" "Le groupe sudo est vide"
    else
        ko "C3" "Le groupe sudo contient encore des utilisateurs"
    fi
}


# C4 : compte root et dossiers personnels
# Fichiers a verifier : installer.sh et creer_comptes.sh
test_C4() {

    etat=$(passwd -S root | cut -d" " -f2)

    if [ "$etat" = "L" ]; then
        ok "C4" "Le compte root est verrouille"
    else
        ko "C4" "Le compte root n'est pas verrouille"
    fi

    # Verifier que les autres ne peuvent pas lire les dossiers
    for utilisateur in nicolas leo dev1 design1 commercial1 freelance1
    do
        if sudo -u support test -r "/home/$utilisateur"; then
            ko "C4" "Le dossier de $utilisateur est accessible"
        else
            ok "C4" "Le dossier de $utilisateur est protege"
        fi
    done
}


# S1 : connexion SSH par cle uniquement
# Fichiers a verifier : config/ssh/ et installer.sh
test_S1() {

    if sshd -T | grep -q "^passwordauthentication no$"; then
        ok "S1" "Connexion par mot de passe desactivee"
    else
        ko "S1" "Connexion par mot de passe activee"
    fi

    if sshd -T | grep -q "^pubkeyauthentication yes$"; then
        ok "S1" "Connexion par cle autorisee"
    else
        ko "S1" "Connexion par cle non autorisee"
    fi

    if sshd -T | grep -q "^kbdinteractiveauthentication no$"; then
        ok "S1" "Authentification interactive desactivee"
    else
        ko "S1" "Authentification interactive activee"
    fi
}


# S2 : connexion root interdite
# Fichiers a verifier : config/ssh/ et installer.sh

test_S2() {

    if sshd -T | grep -q "^permitrootlogin no$"; then
        ok "S2" "Connexion root interdite"
    else
        ko "S2" "Connexion root non interdite"
    fi
}


# S3 : groupe acces_ssh
# Fichiers a verifier : config/ssh/ et creer_comptes.sh

test_S3() {

    if sshd -T | grep -q "^allowgroups acces_ssh$"; then
        ok "S3" "Seul le groupe acces_ssh est autorise"
    else
        ko "S3" "Le groupe acces_ssh n'est pas configure"
    fi
}


# S4 : limites des connexions
# Fichiers a verifier : config/ssh/ et installer.sh
test_S4() {

    if sshd -T | grep -q "^maxauthtries 4$"; then
        ok "S4" "Maximum 4 tentatives de connexion"
    else
        ko "S4" "Le nombre de tentatives est incorrect"
    fi

    if sshd -T | grep -q "^clientaliveinterval 300$"; then
        ok "S4" "Intervalle SSH de 300 secondes"
    else
        ko "S4" "Intervalle SSH incorrect"
    fi

    if sshd -T | grep -q "^clientalivecountmax 3$"; then
        ok "S4" "Limite de controle SSH a 3"
    else
        ko "S4" "Limite de controle SSH incorrecte"
    fi
}


# S5 : fichier de configuration SSH
# Fichiers a verifier : config/ssh/ et installer.sh
test_S5() {

    if [ -f /etc/ssh/sshd_config.d/pixelia.conf ]; then
        ok "S5" "Le fichier de configuration SSH existe"
    else
        ko "S5" "Le fichier de configuration SSH n'existe pas"
    fi

    if sshd -t; then
        ok "S5" "La configuration SSH est valide"
    else
        ko "S5" "La configuration SSH contient une erreur"
    fi
}


# J1 : fail2ban protege SSH
test_J1() {
    if systemctl is-active fail2ban > /dev/null; then
        ok "J1" "fail2ban est demarre"
    else
        ko "J1" "fail2ban n'est pas demarre"
    fi

    if fail2ban-client status sshd > /dev/null 2>&1; then
        ok "J1" "la jail sshd est active"
    else
        ko "J1" "la jail sshd n'est pas active"
    fi

    # Si on lit 3, notre fichier est bien pris en compte
    essais=$(fail2ban-client get sshd maxretry 2> /dev/null)
    if [ "$essais" = "3" ]; then
        ok "J1" "bannissement apres 3 echecs"
    else
        ko "J1" "maxretry vaut '$essais' (attendu : 3)"
    fi
}

# J2 : pare-feu nftables
test_J2() {
    if systemctl is-enabled nftables > /dev/null; then
        ok "J2" "nftables se lance au demarrage"
    else
        ko "J2" "nftables ne se lance pas au demarrage"
    fi

    if nft list chain inet filtre input 2> /dev/null | grep -q "policy drop"; then
        ok "J2" "politique par defaut : drop"
    else
        ko "J2" "la politique par defaut n'est pas drop"
    fi

    if nft list chain inet filtre input 2> /dev/null | grep -q "tcp dport 22 accept"; then
        ok "J2" "SSH (port 22) autorise"
    else
        ko "J2" "SSH (port 22) n'est pas autorise"
    fi

    if nft list chain inet filtre input 2> /dev/null | grep -q "ct state established,related accept"; then
        ok "J2" "connexions etablies autorisees"
    else
        ko "J2" "connexions etablies non autorisees"
    fi
}

# J3 : journal persistant
test_J3() {
    if grep -q "^Storage=persistent" /etc/systemd/journald.conf.d/10-persistent.conf 2> /dev/null; then
        ok "J3" "Storage=persistent est configure"
    else
        ko "J3" "Storage=persistent n'est pas configure"
    fi

    # Le journal persistant est ecrit dans ce dossier
    if [ -d /var/log/journal ]; then
        ok "J3" "le dossier /var/log/journal existe"
    else
        ko "J3" "le dossier /var/log/journal n'existe pas"
    fi
}

# D1 : mises a jour de securite automatiques
test_D1() {
    if dpkg -l unattended-upgrades 2> /dev/null | grep -q "^ii"; then
        ok "D1" "unattended-upgrades est installe"
    else
        ko "D1" "unattended-upgrades n'est pas installe"
    fi

    # apt-config dump affiche la configuration reellement appliquee par apt
    if apt-config dump | grep -q 'APT::Periodic::Unattended-Upgrade "1"'; then
        ok "D1" "les mises a jour automatiques sont activees"
    else
        ko "D1" "les mises a jour automatiques ne sont pas activees"
    fi
}

# J4 : script d'analyse des logs
test_J4() {
    if [ -f /usr/local/sbin/analyse_logs.sh ]; then
        ok "J4" "analyse_logs.sh est installe"
    else
        ko "J4" "analyse_logs.sh absent de /usr/local/sbin"
    fi

    proprietaire=$(ls -l /usr/local/sbin/analyse_logs.sh | cut -d" " -f3)
    if [ "$proprietaire" = "root" ]; then
        ok "J4" "analyse_logs.sh appartient a root"
    else
        ko "J4" "analyse_logs.sh appartient a $proprietaire"
    fi

    if sudo -u support test -w /usr/local/sbin/analyse_logs.sh; then
        ko "J4" "support peut modifier analyse_logs.sh"
    else
        ok "J4" "support ne peut pas modifier analyse_logs.sh"
    fi

    # Avec un seuil tres haut, il ne doit pas y avoir d'alerte : code 0
    if /usr/local/sbin/analyse_logs.sh 100000 > /dev/null; then
        ok "J4" "analyse_logs.sh renvoie 0 sous le seuil"
    else
        ko "J4" "analyse_logs.sh ne renvoie pas 0 sous le seuil"
    fi

    # Avec un seuil qui n'est pas un nombre, il doit refuser
    if /usr/local/sbin/analyse_logs.sh abc > /dev/null 2>&1; then
        ko "J4" "analyse_logs.sh accepte un seuil invalide"
    else
        ok "J4" "analyse_logs.sh refuse un seuil invalide"
    fi
}


# B1 : sauvegarde incrementale avec versions datees
test_B1() {
    if mountpoint -q /sauvegardes; then
        ok "B1" "le second disque est monte sur /sauvegardes"
    else
        ko "B1" "/sauvegardes n'est pas monte"
    fi

    if grep -q "/sauvegardes" /etc/fstab; then
        ok "B1" "le montage est dans /etc/fstab (permanent)"
    else
        ko "B1" "le montage n'est pas dans /etc/fstab"
    fi

    if grep -q -- "--link-dest" /usr/local/sbin/sauvegarde.sh 2> /dev/null; then
        ok "B1" "sauvegarde.sh est incrementale (--link-dest)"
    else
        ko "B1" "sauvegarde.sh n'utilise pas --link-dest"
    fi

    nombre=$(ls -1 /sauvegardes/versions 2> /dev/null | wc -l)
    if [ "$nombre" -ge 1 ] && [ "$nombre" -le 7 ]; then
        ok "B1" "$nombre version(s) de sauvegarde (7 maximum)"
    else
        ko "B1" "$nombre version(s) de sauvegarde (attendu : entre 1 et 7)"
    fi

    # Les ACL doivent etre gardees dans la sauvegarde
    derniere=$(ls -1 /sauvegardes/versions 2> /dev/null | tail -n 1)
    if getfacl "/sauvegardes/versions/$derniere/srv/projets" 2> /dev/null | grep -q "default:group:dev:rwx"; then
        ok "B1" "les ACL sont gardees dans la sauvegarde"
    else
        ko "B1" "les ACL ne sont pas dans la sauvegarde"
    fi
}

# B2 : sauvegarde planifiee et journalisee
test_B2() {
    if grep -q "/usr/local/sbin/sauvegarde.sh" /etc/cron.d/sauvegarde 2> /dev/null; then
        ok "B2" "la sauvegarde est planifiee dans /etc/cron.d/sauvegarde"
    else
        ko "B2" "pas de planification dans /etc/cron.d/sauvegarde"
    fi

    if systemctl is-active cron > /dev/null; then
        ok "B2" "le service cron est demarre"
    else
        ko "B2" "le service cron n'est pas demarre"
    fi

    if [ -s /var/log/sauvegarde.log ]; then
        ok "B2" "le journal /var/log/sauvegarde.log existe"
    else
        ko "B2" "pas de journal /var/log/sauvegarde.log"
    fi
}

# B3 : sauvegardes accessibles seulement aux admins
test_B3() {
    if sudo -u leo test -r /sauvegardes; then
        ok "B3" "leo (admins) peut lire /sauvegardes"
    else
        ko "B3" "leo (admins) ne peut pas lire /sauvegardes"
    fi

    for login in dev1 support freelance1
    do
        if sudo -u "$login" test -r /sauvegardes; then
            ko "B3" "$login peut lire /sauvegardes"
        else
            ok "B3" "$login ne peut pas lire /sauvegardes"
        fi
    done
}


# Lancer les tests
test_C1
test_C2
test_C3
test_C4
test_S1
test_S2
test_S3
test_S4
test_S5
test_J1
test_J2
test_J3
test_J4
test_D1
test_B1
test_B2
test_B3

echo "--- $tests_reussis / $nombre_tests tests reussis"

if [ "$tests_reussis" -eq "$nombre_tests" ]; then
    exit 0
else
    exit 1
fi
