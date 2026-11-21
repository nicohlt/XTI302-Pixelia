#!/bin/bash
# Création des groupes

if [ "$EUID" -ne 0 ]; then
    echo "Il faut lancer ce script avec sudo"
    exit 1
fi

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

    fi
done < comptes.csv

echo "Utilisateurs terminés"

for fichier in config/cles/*.pub
do
  login=$(basename "$fichier" .pub)
    if id "$login" > /dev/null 2>&1; then
      mkdir -p "/home/$login/.ssh"
      cp "$fichier" "/home/$login/.ssh/authorized_keys"

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

