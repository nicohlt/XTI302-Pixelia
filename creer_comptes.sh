#!/bin/bash
# Creation des groupes, des comptes, des cles SSH et des dossiers de /srv
# a partir du fichier comptes.csv

set -euo pipefail

# On fixe le PATH : avec "su -c" il ne contient pas /usr/sbin
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Date de fin du semestre : les comptes freelance expirent ce jour la
DATE_FIN="2027-01-31"

if [ "$EUID" -ne 0 ]; then
    echo "Il faut lancer ce script avec sudo"
    exit 1
fi

# Le script doit etre lance depuis le dossier du projet
if [ ! -f comptes.csv ]; then
    echo "Erreur : comptes.csv introuvable, lancez le script depuis le dossier du projet" >&2
    exit 2
fi

# Création des groupes

for groupe in admins acces_ssh support dev design commercial freelance
do
    if ! getent group "$groupe" > /dev/null; then
        groupadd "$groupe"
        echo "Groupe cree : $groupe"
    fi
done

echo "Groupe Terminé"

while IFS=";" read -r login nom groupe autres
do
    if [ "$login" != "login" ]; then

        if ! id "$login" > /dev/null 2>&1; then
            useradd -m -s /bin/bash -g "$groupe" "$login"
            echo "Utilisateur cree : $login"
        fi
	usermod -g "$groupe" "$login"

        if [ -n "$autres" ]; then
            usermod -aG "$autres" "$login"
        fi

        # Les freelance expirent a la fin du semestre
        if [ "$groupe" = "freelance" ]; then
            chage -E "$DATE_FIN" "$login"
            echo "Compte $login expire le $DATE_FIN"
        fi

    fi
done < comptes.csv

echo "Utilisateurs terminés"

for fichier in config/cles/*.pub
do
  login=$(basename "$fichier" .pub)
    if id "$login" > /dev/null 2>&1; then
      mkdir -p "/home/$login/.ssh"
      touch "/home/$login/.ssh/authorized_keys"
      
      # Verifie si la cle SSH est deja presente
      # Si elle est absente on l'ajoute sans supprimer les autres cles
      if ! grep -qxF -f "$fichier" "/home/$login/.ssh/authorized_keys"; then
        cat "$fichier" >> "/home/$login/.ssh/authorized_keys"
      fi
      chmod 700 "/home/$login/.ssh"
      chmod 600 "/home/$login/.ssh/authorized_keys"
      chown -R "$login" "/home/$login/.ssh"

      echo "Cle SSH installee pour $login"
    fi
done


#TEsts dossiers

mkdir -p /srv/projets/externe
mkdir -p /srv/maquettes
mkdir -p /srv/clients

# ACL config + permissions

setfacl -m g:dev:rwx,g:design:rx,g:freelance:--x,o::--- /srv/projets
setfacl -m g:dev:rwx,g:design:rx,g:freelance:rwx,o::--- /srv/projets/externe
setfacl -m g:dev:rx,g:design:rwx,g:commercial:rx,o::--- /srv/maquettes
setfacl -m g:commercial:rwx,o::--- /srv/clients

echo "Permissions ACL correctement config !"

# ACL par defaut

setfacl -d -m g:dev:rwx,g:design:rx,o::--- /srv/projets
setfacl -d -m g:dev:rwx,g:design:rx,g:freelance:rwx,o::--- /srv/projets/externe
setfacl -d -m g:dev:rx,g:design:rwx,g:commercial:rx,o::--- /srv/maquettes
setfacl -d -m g:commercial:rwx,o::--- /srv/clients

echo "ACL par defaut bien config !"

while IFS=";" read -r login nom groupe autres #securisation des doss
do
    if [ "$login" != "login" ]; then
        chmod 700 "/home/$login"
    fi
done < comptes.csv

echo "Dossiers personnels proteges"

