#!/bin/bash
# Verifie que le serveur respecte le cahier des charges
# A lancer depuis le dossier du projet : sudo ./verifier.sh
# Code de sortie : 0 si tout est bon, 1 sinon

# Pas de set -e : les tests peuvent echouer et on veut voir tous les resultats

TOTAL=0
REUSSIS=0

if [ "$EUID" -ne 0 ]; then
    echo "Il faut lancer ce script avec sudo"
    exit 1
fi

if [ ! -f comptes.csv ]; then
    echo "Erreur : lancez le script depuis le dossier du projet" >&2
    exit 2
fi

ok() {
    echo "[OK] $1 $2"
    TOTAL=$(( TOTAL + 1 ))
    REUSSIS=$(( REUSSIS + 1 ))
}

ko() {
    echo "[KO] $1 $2"
    TOTAL=$(( TOTAL + 1 ))
}


# C1 : comptes et groupes
test_C1() {
    for groupe in admins acces_ssh support dev design commercial freelance
    do
        if getent group "$groupe" > /dev/null; then
            ok "C1" "le groupe $groupe existe"
        else
            ko "C1" "le groupe $groupe n'existe pas"
        fi
    done

    # On relit comptes.csv
    while IFS=";" read -r login nom groupe autres
    do
        if [ "$login" != "login" ]; then
            if id "$login" > /dev/null 2>&1; then
                ok "C1" "le compte $login existe"
            else
                ko "C1" "le compte $login n'existe pas"
            fi

            if id -nG "$login" | grep -q "$groupe"; then
                ok "C1" "$login est dans le groupe $groupe"
            else
                ko "C1" "$login n'est pas dans le groupe $groupe"
            fi

            if [ -n "$autres" ]; then
                if id -nG "$login" | grep -q "$autres"; then
                    ok "C1" "$login est dans le groupe $autres"
                else
                    ko "C1" "$login n'est pas dans le groupe $autres"
                fi
            fi
        fi
    done < comptes.csv

    # Les freelance doivent avoir une date d'expiration
    # (8eme champ de /etc/shadow, vide si le compte n'expire jamais)
    for login in freelance1 freelance2
    do
        expiration=$(getent shadow "$login" | cut -d: -f8)
        if [ -n "$expiration" ]; then
            ok "C1" "le compte $login a une date d'expiration"
        else
            ko "C1" "le compte $login n'expire jamais"
        fi
    done
}


# C2 : droits sur les dossiers de /srv
test_C2() {
    if sudo -u dev1 test -w /srv/projets; then
        ok "C2" "dev1 peut ecrire dans /srv/projets"
    else
        ko "C2" "dev1 ne peut pas ecrire dans /srv/projets"
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

    # ACL par defaut (pour les fichiers crees plus tard)
    if getfacl /srv/projets 2> /dev/null | grep -q "default:group:dev:rwx"; then
        ok "C2" "ACL par defaut sur /srv/projets"
    else
        ko "C2" "pas d'ACL par defaut sur /srv/projets"
    fi
}


# C3 : sudo
test_C3() {
    if sudo -l -U leo | grep -q "(ALL : ALL) ALL"; then
        ok "C3" "leo (admins) a sudo"
    else
        ko "C3" "leo (admins) n'a pas sudo"
    fi

    if sudo -l -U support | grep -q "analyse_logs.sh"; then
        ok "C3" "support peut lancer analyse_logs.sh"
    else
        ko "C3" "support ne peut pas lancer analyse_logs.sh"
    fi

    if sudo -l -U support | grep -q "(ALL : ALL) ALL"; then
        ko "C3" "support a tous les droits sudo"
    else
        ok "C3" "support n'a pas tous les droits sudo"
    fi

    # Les comptes metier ne doivent avoir aucun droit sudo
    for login in dev1 design1 commercial1 freelance1
    do
        if sudo -l -U "$login" | grep -q "ALL"; then
            ko "C3" "$login a des droits sudo"
        else
            ok "C3" "$login n'a pas sudo"
        fi
    done

    # Le groupe sudo de Debian doit etre vide
    membres=$(getent group sudo | cut -d: -f4)
    if [ -z "$membres" ]; then
        ok "C3" "personne dans le groupe sudo"
    else
        ko "C3" "le groupe sudo contient : $membres"
    fi
}


# C4 : root verrouille et dossiers personnels prives
test_C4() {
    # passwd -S affiche L en 2eme colonne si le compte est verrouille
    etat=$(passwd -S root | cut -d" " -f2)
    if [ "$etat" = "L" ]; then
        ok "C4" "le compte root est verrouille"
    else
        ko "C4" "le compte root n'est pas verrouille"
    fi

    for login in leo nicolas dev1
    do
        if sudo -u commercial1 test -r "/home/$login"; then
            ko "C4" "commercial1 peut lire /home/$login"
        else
            ok "C4" "commercial1 ne peut pas lire /home/$login"
        fi
    done
}


# S1 : connexion par cle uniquement
test_S1() {
    if sshd -T | grep -qi "^passwordauthentication no$"; then
        ok "S1" "connexion par mot de passe refusee"
    else
        ko "S1" "PasswordAuthentication n'est pas a 'no'"
    fi

    if sshd -T | grep -qi "^pubkeyauthentication yes$"; then
        ok "S1" "connexion par cle autorisee"
    else
        ko "S1" "PubkeyAuthentication n'est pas a 'yes'"
    fi
}

# S2 : pas de connexion root
test_S2() {
    if sshd -T | grep -qi "^permitrootlogin no$"; then
        ok "S2" "connexion root refusee"
    else
        ko "S2" "PermitRootLogin n'est pas a 'no'"
    fi
}

# S3 : seul le groupe acces_ssh peut se connecter
test_S3() {
    if sshd -T | grep -qi "^allowgroups acces_ssh$"; then
        ok "S3" "seul le groupe acces_ssh peut se connecter"
    else
        ko "S3" "AllowGroups n'est pas a 'acces_ssh'"
    fi
}

# S4 : 4 essais maximum, session inactive fermee apres 15 minutes
test_S4() {
    if sshd -T | grep -qi "^maxauthtries 4$"; then
        ok "S4" "4 essais maximum par connexion"
    else
        ko "S4" "MaxAuthTries n'est pas a 4"
    fi

    # 300 secondes x 3 = 900 secondes = 15 minutes
    if sshd -T | grep -qi "^clientaliveinterval 300$"; then
        ok "S4" "ClientAliveInterval a 300"
    else
        ko "S4" "ClientAliveInterval n'est pas a 300"
    fi

    if sshd -T | grep -qi "^clientalivecountmax 3$"; then
        ok "S4" "ClientAliveCountMax a 3"
    else
        ko "S4" "ClientAliveCountMax n'est pas a 3"
    fi
}

# S5 : config dans sshd_config.d et sans erreur
test_S5() {
    if [ -f /etc/ssh/sshd_config.d/pixelia.conf ]; then
        ok "S5" "pixelia.conf est dans /etc/ssh/sshd_config.d/"
    else
        ko "S5" "pixelia.conf absent de /etc/ssh/sshd_config.d/"
    fi

    if sshd -t; then
        ok "S5" "sshd -t ne trouve pas d'erreur"
    else
        ko "S5" "sshd -t trouve une erreur"
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


# Lancement de tous les tests
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

echo "--- $REUSSIS / $TOTAL tests reussis"

if [ "$REUSSIS" -eq "$TOTAL" ]; then
    exit 0
else
    exit 1
fi
