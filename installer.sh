#!/bin/bash
# Installation de la configuration du serveur Pixelia
# A lancer depuis le dossier du projet : sudo ./installer.sh

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Il faut lancer ce script avec sudo"
    exit 1
fi

if [ ! -f comptes.csv ]; then
    echo "Erreur : lancez le script depuis le dossier du projet" >&2
    exit 2
fi

# Paquets
apt-get update
apt-get install -y sudo acl
echo "Paquets installes"

# Comptes, groupes, cles SSH et dossiers /srv
bash creer_comptes.sh

# Fichiers sudo
for fichier in config/sudoers.d/*
do
    # On verifie le fichier avec visudo avant de le copier
    if ! visudo -c -f "$fichier"; then
        echo "Erreur dans $fichier, on arrete" >&2
        exit 3
    fi
    cp "$fichier" /etc/sudoers.d/
    echo "Copie de $fichier dans /etc/sudoers.d"
done

chmod 440 /etc/sudoers.d/admins
chmod 440 /etc/sudoers.d/support

# Script d'analyse des logs (J4)
# Il appartient a root et seul root peut le modifier : support le lance
# en root avec sudo, s'il pouvait le modifier il deviendrait root
cp analyse_logs.sh /usr/local/sbin/analyse_logs.sh
chown root:root /usr/local/sbin/analyse_logs.sh
chmod 755 /usr/local/sbin/analyse_logs.sh
echo "analyse_logs.sh installe dans /usr/local/sbin"

# Mot de passe des admins : il sert pour sudo
# et pour la console de la VM quand root sera verrouille
for admin in nicolas leo
do
    read -r -p "Definir le mot de passe de $admin ? (o/n) : " REPONSE
    if [ "$REPONSE" = "o" ]; then
        passwd "$admin"
    fi
done

# Debian donne sudo au compte cree pendant l'installation (groupe sudo)
# On le retire : seuls les admins doivent avoir sudo
for utilisateur in $(getent group sudo | cut -d: -f4 | tr "," " ")
do
    deluser "$utilisateur" sudo
    echo "$utilisateur n'est plus dans le groupe sudo"
done

# On verrouille root a la fin, quand les admins ont sudo
passwd -l root
echo "Compte root verrouille"

# Configuration SSH
cp config/ssh/sshd_config.d/pixelia.conf /etc/ssh/sshd_config.d/pixelia.conf

# Verifier la configuration avant de redemarrer SSH
if sshd -t; then
    systemctl restart ssh
    echo "SSH configure"
else
    echo "Erreur dans la configuration SSH"
    exit 1
fi

echo "Installation terminee"
