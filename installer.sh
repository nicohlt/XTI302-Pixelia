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
apt-get install -y sudo acl nftables fail2ban python3-systemd unattended-upgrades rsync cron parted
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

# Pare-feu nftables (J2)
# nft -c verifie le fichier sans l'appliquer
if nft -c -f config/nftables.conf; then
    cp config/nftables.conf /etc/nftables.conf
    # enable : le pare-feu redemarre tout seul apres un reboot
    systemctl enable nftables
    systemctl restart nftables
    echo "Pare-feu configure"
else
    echo "Erreur dans config/nftables.conf" >&2
    exit 4
fi

# fail2ban (J1), apres nftables car il ajoute ses regles dans le pare-feu
cp config/fail2ban/jail.d/pixelia.conf /etc/fail2ban/jail.d/pixelia.conf
if fail2ban-client -t; then
    systemctl enable fail2ban
    systemctl restart fail2ban
    echo "fail2ban configure"
else
    echo "Erreur dans la configuration fail2ban" >&2
    exit 5
fi

# Journal persistant (J3)
mkdir -p /etc/systemd/journald.conf.d
cp config/journald.conf.d/10-persistent.conf /etc/systemd/journald.conf.d/10-persistent.conf
systemctl restart systemd-journald
echo "Journal persistant configure"

# Mises a jour de securite automatiques (D1)
cp config/apt/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades
systemctl enable unattended-upgrades
echo "Mises a jour automatiques configurees"

# ---------- Sauvegarde (B1, B2, B3) ----------

# Le second disque de la VM s'appelle /dev/sdb
if [ ! -b /dev/sdb ]; then
    echo "Erreur : pas de second disque /dev/sdb pour les sauvegardes" >&2
    exit 6
fi

# On partitionne et on formate SEULEMENT si la partition n'existe pas encore.
# Si on relance installer.sh, on ne reformate pas : les sauvegardes sont gardees.
if [ ! -b /dev/sdb1 ]; then
    parted -s /dev/sdb mklabel gpt
    parted -s /dev/sdb mkpart primary ext4 0% 100%
    # on attend que le systeme voie la nouvelle partition
    sleep 2
    mkfs.ext4 /dev/sdb1
    echo "Second disque partitionne et formate"
else
    echo "La partition /dev/sdb1 existe deja, on ne la reformate pas"
fi

# Montage permanent : une ligne dans /etc/fstab (lue a chaque demarrage)
# On utilise l'UUID de la partition : il ne change pas, meme si le nom sdb change
mkdir -p /sauvegardes
if ! grep -q "/sauvegardes" /etc/fstab; then
    UUID=$(blkid -s UUID -o value /dev/sdb1)
    echo "UUID=$UUID /sauvegardes ext4 defaults 0 2" >> /etc/fstab
    systemctl daemon-reload
    echo "Montage ajoute dans /etc/fstab"
fi

if ! mountpoint -q /sauvegardes; then
    mount /sauvegardes
fi

# B3 : seuls root et le groupe admins peuvent entrer dans /sauvegardes
mkdir -p /sauvegardes/versions
chown root:admins /sauvegardes
chmod 750 /sauvegardes
echo "Dossier /sauvegardes reserve aux admins"

# Le script appartient a root, lui seul peut le lire et le modifier
cp sauvegarde.sh /usr/local/sbin/sauvegarde.sh
chown root:root /usr/local/sbin/sauvegarde.sh
chmod 700 /usr/local/sbin/sauvegarde.sh

# B2 : planification avec cron
cp config/cron.d/sauvegarde /etc/cron.d/sauvegarde
chown root:root /etc/cron.d/sauvegarde
chmod 644 /etc/cron.d/sauvegarde
systemctl enable cron
systemctl restart cron
echo "Sauvegarde planifiee tous les jours a 2h"

# Premiere sauvegarde tout de suite
/usr/local/sbin/sauvegarde.sh >> /var/log/sauvegarde.log 2>&1
echo "Premiere sauvegarde faite (journal : /var/log/sauvegarde.log)"

echo "Installation terminee"
