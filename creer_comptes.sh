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

echo "Termine"
