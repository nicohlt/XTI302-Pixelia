# Projet AS Cyber

Contexte A : Agence web Pixelia

Objectif : durcir un serveur Debian 13 avec des scripts Bash.

## Installation

Sur la VM Debian 13 vierge (sudo n'est pas encore installé, on utilise root) :

```
su -c 'apt-get install -y git'
git clone https://github.com/nicohlt/XTI302-Pixelia.git
cd XTI302-Pixelia
su -c 'bash installer.sh'
```
`ssh -t -p 2225 -i C:\Users\Leo\.ssh\id_pixelia leo@127.0.0.1`  

Si sudo est déjà installé : `sudo bash installer.sh`

## Vérification

```
sudo bash verifier.sh
```
