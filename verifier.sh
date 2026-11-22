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

echo "----------------------------"
echo "$tests_reussis tests reussis sur $nombre_tests"

if [ "$tests_reussis" -eq "$nombre_tests" ]; then
    exit 0
else
    exit 1
fi
