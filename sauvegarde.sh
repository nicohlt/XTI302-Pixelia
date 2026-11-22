#!/bin/bash
# sauvegarde.sh - sauvegarde incrementale de /srv et /etc sur le second disque
# Chaque execution cree une version datee dans /sauvegardes/versions
# On garde les 7 dernieres versions, les plus anciennes sont supprimees
# Lance par cron tous les jours (voir config/cron.d/sauvegarde)

set -euo pipefail

# Chemins absolus partout : cron ne part pas du meme dossier que nous
VERSIONS="/sauvegardes/versions"
GARDER=7
DATE=$(date +%Y-%m-%d_%H-%M-%S)
NOUVELLE="$VERSIONS/$DATE"

if [ "$EUID" -ne 0 ]; then
    echo "Il faut lancer ce script avec sudo" >&2
    exit 1
fi

# Si le second disque n'est pas monte, on arrete :
# sinon on remplirait le disque systeme
if ! mountpoint -q /sauvegardes; then
    echo "$(date) : ERREUR le disque /sauvegardes n'est pas monte" >&2
    exit 2
fi

mkdir -p "$VERSIONS"

echo "$(date) : debut de la sauvegarde $DATE"

# La derniere version (les noms sont des dates, donc ls les trie dans l'ordre)
DERNIERE=$(ls -1 "$VERSIONS" | tail -n 1)

# -a : garde les droits, proprietaires, dates
# -A : garde les ACL
if [ -z "$DERNIERE" ]; then
    # Premiere sauvegarde : on copie tout
    rsync -aA /srv /etc "$NOUVELLE/"
else
    # Sauvegarde incrementale : --link-dest compare avec la version precedente.
    # Les fichiers qui n'ont pas change ne sont pas recopies : on fait juste
    # un lien vers le fichier de la version precedente (ca ne prend pas de place)
    rsync -aA --link-dest="$VERSIONS/$DERNIERE" /srv /etc "$NOUVELLE/"
fi

echo "$(date) : version $DATE creee"

# On garde seulement les 7 dernieres versions
NOMBRE=$(ls -1 "$VERSIONS" | wc -l)
while [ "$NOMBRE" -gt "$GARDER" ]
do
    PLUS_VIEILLE=$(ls -1 "$VERSIONS" | head -n 1)
    # securite : on ne lance jamais rm -rf avec un nom vide
    if [ -n "$PLUS_VIEILLE" ]; then
        rm -rf "$VERSIONS/$PLUS_VIEILLE"
        echo "$(date) : ancienne version $PLUS_VIEILLE supprimee"
    fi
    NOMBRE=$(( NOMBRE - 1 ))
done

echo "$(date) : sauvegarde terminee, $GARDER versions maximum gardees"
exit 0
