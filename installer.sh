#!/bin/bash
# Installation de toute la configuration du serveur Pixelia
# A lancer en root depuis le dossier du depot : sudo ./installer.sh
# Le script peut etre relance sans danger.

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Il faut lancer ce script avec sudo"
    exit 1
fi

# On se place dans le dossier du script
DOSSIER_SCRIPT=$(dirname "$0")
cd "$DOSSIER_SCRIPT"


# ---------- Paquets ----------

echo "Installation des paquets..."
apt-get update
apt-get install -y sudo acl

echo "Paquets installes"


# ---------- Comptes (C1, C2, C4) ----------

bash ./creer_comptes.sh


# ---------- Sudo (C3) ----------

for fichier in config/sudoers.d/*
do
    nom=$(basename "$fichier")

    # On verifie la syntaxe AVANT de copier
    # (un fichier sudoers faux peut casser sudo pour tout le monde)
    if ! visudo -c -f "$fichier"; then
        echo "Erreur : le fichier $fichier a une erreur de syntaxe"
        exit 1
    fi

    cp "$fichier" "/etc/sudoers.d/$nom"
    chown root:root "/etc/sudoers.d/$nom"
    chmod 440 "/etc/sudoers.d/$nom"
    echo "Fichier sudoers installe : $nom"
done

# Les admins doivent avoir un mot de passe pour utiliser sudo
# et pour se connecter a la console de la VM si SSH ne marche plus.
# Le mot de passe n'est jamais dans le depot : on le demande ici.
# On prend les admins dans comptes.csv (admins = leur groupe principal)
while IFS=";" read -r login nom groupe autres
do
    if [ "$groupe" = "admins" ]; then
        # passwd -S affiche "P" en 2eme colonne si le mot de passe existe
        etat=$(passwd -S "$login" | cut -d" " -f2)
        if [ "$etat" != "P" ]; then
            echo "Le compte $login n'a pas de mot de passe, il faut en choisir un :"
            # < /dev/tty : on lit le clavier et pas le fichier comptes.csv
            passwd "$login" < /dev/tty
        fi
    fi
done < comptes.csv

# Debian donne sudo au compte cree pendant l'installation (groupe sudo).
# On l'enleve : seuls les admins doivent avoir sudo.
membres_sudo=$(getent group sudo | cut -d: -f4 | tr ',' ' ')
for utilisateur in $membres_sudo
do
    gpasswd -d "$utilisateur" sudo
    echo "$utilisateur retire du groupe sudo"
done


# ---------- Root (C4) ----------

# On verrouille root seulement a la fin, quand les admins ont sudo
passwd -l root
echo "Compte root verrouille"
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
