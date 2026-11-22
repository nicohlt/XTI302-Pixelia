#!/bin/bash
# analyse_logs.sh - rapport des connexions SSH des dernieres 24 heures
# Usage : analyse_logs.sh [seuil]
#   seuil = nombre d'echecs d'une meme IP qui declenche une alerte (10 par defaut)
# Code de sortie : 0 si tout va bien, 1 si une IP atteint le seuil, 2 si erreur

# Pas de set -e : grep renvoie 1 quand il ne trouve rien, ce n'est pas une erreur ici

usage() {
    echo "Usage : $0 [seuil]" >&2
    echo "  seuil : nombre d'echecs par IP avant alerte (10 par defaut)" >&2
    exit 2
}

if [ "$EUID" -ne 0 ]; then
    echo "Il faut lancer ce script avec sudo" >&2
    exit 2
fi

if [ "$#" -gt 1 ]; then
    usage
fi

SEUIL="${1:-10}"

# Le seuil doit etre un nombre
if ! echo "$SEUIL" | grep -qE '^[0-9]+$'; then
    usage
fi

# Sur Debian 13 il n'y a pas de /var/log/auth.log : on lit le journal avec journalctl
JOURNAL=$(journalctl -u ssh --since "24 hours ago" --no-pager)

# Forme d'une adresse IP : 4 blocs de 1 a 3 chiffres separes par des points
IP='([0-9]{1,3}\.){3}[0-9]{1,3}'

echo "===== Rapport SSH des dernieres 24 heures ====="
echo "Seuil d'alerte : $SEUIL echecs par adresse IP"
echo

# Un echec s'ecrit de 3 facons :
#   Failed password  : mot de passe faux
#   Invalid user     : le compte n'existe pas
#   not allowed      : le compte existe mais n'est pas dans acces_ssh
ECHECS=$(echo "$JOURNAL" | grep -E 'Failed password|Invalid user|not allowed because')

echo "--- Echecs par adresse IP ---"
ECHECS_PAR_IP=$(echo "$ECHECS" | grep -oE "$IP" | sort | uniq -c | sort -rn)
if [ -z "$ECHECS_PAR_IP" ]; then
    echo "Aucun echec"
else
    echo "$ECHECS_PAR_IP"
fi
echo

echo "--- Comptes vises ---"
echo "Comptes qui n'existent pas :"
echo "$JOURNAL" | grep -oE 'Invalid user [^ ]+' | sort | uniq -c | sort -rn
echo "Comptes refuses (pas dans acces_ssh) :"
echo "$JOURNAL" | grep -oE 'User [^ ]+ from' | sort | uniq -c | sort -rn
echo

echo "--- Connexions reussies ---"
REUSSIES=$(echo "$JOURNAL" | grep 'Accepted' | grep -oE "for [^ ]+ from $IP" | sort | uniq -c | sort -rn)
if [ -z "$REUSSIES" ]; then
    echo "Aucune connexion reussie"
else
    echo "$REUSSIES"
fi
echo

# On regarde chaque IP : si elle a autant d'echecs que le seuil, alerte
ALERTE=0
while read -r nombre adresse
do
    if [ -n "$nombre" ] && [ "$nombre" -ge "$SEUIL" ]; then
        echo "ALERTE : $adresse a $nombre echecs (seuil : $SEUIL)"
        ALERTE=1
    fi
done << FIN
$ECHECS_PAR_IP
FIN

if [ "$ALERTE" -eq 1 ]; then
    exit 1
else
    echo "Aucune adresse n'atteint le seuil"
    exit 0
fi
