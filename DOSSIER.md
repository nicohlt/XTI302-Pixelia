# Dossier projet XTI302 - Pixelia

Nicolas et Léo - Contexte A (agence web Pixelia) - Debian 13

Pour l'ANSSI on a utilisé le guide de configuration Linux (BP-028 v2.0) et le guide OpenSSH (NT-007).

## 1. Tableau de conformité

| Exigence | Ce qu'on a fait | Test | ANSSI |
|---|---|---|---|
| C1 | creer_comptes.sh lit comptes.csv et cree les groupes et les comptes seulement s'ils existent pas. Les freelance expirent le 31/01/2027 avec chage -E | test_C1 | NT-007 R21, BP-028 R30 |
| C2 | Dossiers de /srv avec setfacl (ACL + ACL par defaut avec -d), les autres n'ont aucun droit | test_C2 | BP-028 R50 |
| C3 | Fichiers dans config/sudoers.d : admins a tout, support a seulement analyse_logs.sh. On vide le groupe sudo de Debian | test_C3 | BP-028 R38 |
| C4 | passwd -l root et chmod 700 sur les dossiers perso | test_C4 | BP-028 R33, R50 |
| S1 | PasswordAuthentication no, connexion par cle seulement | test_S1 | NT-007 R17 |
| S2 | PermitRootLogin no | test_S2 | NT-007 R21 |
| S3 | AllowGroups acces_ssh | test_S3 | NT-007 R22 |
| S4 | MaxAuthTries 4, ClientAliveInterval 300, ClientAliveCountMax 3 | test_S4 | NT-007 R18 |
| S5 | config dans sshd_config.d/pixelia.conf, sshd -t avant le restart | test_S5 | - |
| J1 | fail2ban avec une jail sshd | test_J1 | BP-028 R79 |
| J2 | nftables avec policy drop, on laisse passer SSH et les connexions etablies | test_J2 | BP-028 R80 |
| J3 | Storage=persistent pour journald | test_J3 | BP-028 R71 |
| J4 | analyse_logs.sh (echecs par IP, comptes vises, connexions reussies) | test_J4 | BP-028 R79 |
| D1 | unattended-upgrades | test_D1 | BP-028 R61 |
| D2 | seul SSH ecoute (voir plus bas) | test_D2 | BP-028 R62 |
| D3 | pas de fichier modifiable par tous, SUID listes plus bas | test_D3 | BP-028 R54, R56, R57 |
| B1 | sauvegarde.sh avec rsync -aA et --link-dest, versions datees, on en garde 7 | test_B1 | - |
| B2 | cron tous les jours a 2h, la sortie va dans /var/log/sauvegarde.log | test_B2 | - |
| B3 | /sauvegardes en root:admins et chmod 750 | test_B3 | BP-028 R50 |
| B4 | restauration testee (partie 4) | test a la main | - |

## 2. Choix techniques

**Comptes**
- Les freelance expirent le 31/01/2027 parce que c'est la fin du semestre.
- Les admins doivent taper leur mot de passe pour sudo. Comme ça si quelqu'un vole la cle SSH il est pas root direct. Et comme root est verrouillé, c'est aussi ce mot de passe qui sert sur la console de la VM si SSH marche plus.
- support a NOPASSWD car il a pas de mot de passe (il se connecte avec une cle). Mais ça marche que pour analyse_logs.sh.
- analyse_logs.sh appartient a root et seul root peut le modifier. Sinon support pourrait mettre ce qu'il veut dedans et le lancer en root avec sudo.
- On a mis des ACL par defaut pour que les fichiers crees plus tard aient aussi les bons droits.
- Freelance a juste le droit x sur /srv/projets pour pouvoir aller dans externe sans voir le reste.

**SSH**
- MaxAuthTries 4 : c'est le maximum demandé. On a pas mis moins car le client SSH peut essayer plusieurs cles et chaque cle compte comme un essai.
- ClientAliveInterval 300 et ClientAliveCountMax 3 : 300 x 3 = 900 secondes donc une session inactive est coupee au bout de 15 min.

**fail2ban**
- 3 echecs en 10 min = banni 10 min. Comme on se connecte tous avec des cles, 3 echecs c'est surement un robot.
- On a mis 10 min de ban pour pas rester bloqués trop longtemps si on se bannit nous meme en testant (sinon `fail2ban-client set sshd unbanip IP`).
- backend = systemd car sur Debian 13 il y a pas de /var/log/auth.log.

**Pare-feu**
- policy drop : tout est bloqué sauf ce qu'on autorise.
- On accepte aussi lo (la machine qui se parle a elle meme).
- On a pas mis `flush ruleset` parce que ça supprime aussi les regles de fail2ban quand on recharge nftables. On supprime et recree juste notre table.

**analyse_logs.sh**
- Seuil de 10 echecs par IP sur 24h (on peut le changer en argument). On s'est dit qu'un admin se trompe presque jamais avec une cle donc 10 echecs dans la journée depuis la meme IP c'est une attaque.

**Sauvegarde**
- --link-dest : les fichiers qui ont pas changé ne sont pas recopiés, rsync fait un lien vers la version d'avant. Ça prend presque pas de place.
- 7 versions = une semaine, si on se rend compte d'un probleme quelques jours apres on peut revenir avant.
- 2h du matin parce que personne travaille a cette heure.
- installer.sh formate le disque seulement si /dev/sdb1 existe pas, comme ça on peut le relancer sans perdre les sauvegardes.
- Dans fstab on utilise l'UUID car le nom sdb peut changer.
- sauvegarde.sh verifie que le disque est monté avant, sinon il remplirait le disque systeme.

**Mises a jour** : par defaut unattended-upgrades installe que les mises a jour de securité, c'est ce qu'on veut.

**D2 - ce qui ecoute** (avec ss -tulpn) :
- TCP 22 : SSH, c'est normal
- UDP 68 : client DHCP, la VM s'en sert pour avoir son IP
- UDP 546 : pareil mais en IPv6

Les ports 68 et 546 c'est des clients pas des serveurs, et le pare-feu bloque quand meme ce qui arrive de l'exterieur.

**D3 - fichiers SUID** (un fichier SUID se lance avec les droits du proprietaire donc root ici) :
- passwd : changer son mot de passe (il doit ecrire dans /etc/shadow)
- chfn, chsh : changer ses infos et son shell
- su : changer d'utilisateur
- sudo : lancer une commande en root si on a le droit
- newgrp, gpasswd : changer de groupe / gerer les groupes
- mount, umount : monter un disque
- ssh-keysign : utilisé par SSH
- dbus-daemon-launch-helper : lancer des services systeme

Ils sont tous installés par Debian et necessaires. verifier.sh met un KO si un nouveau fichier SUID apparait.

## 3. Defense

Ce que notre config rend plus dur :
1. **Force brute SSH** : les mots de passe sont refusés en SSH donc ça sert a rien de les deviner, et fail2ban bannit apres 3 echecs.
2. **Vol de mot de passe** : sans la cle on peut pas se connecter en SSH. Et root est verrouillé et interdit en SSH.
3. **Utilisateur curieux** : un commercial peut pas lire /srv/projets et personne peut lire le dossier perso des autres.
4. **Compte freelance piraté** : pas de sudo, pas de SSH, il peut ecrire que dans externe et en plus le compte expire.
5. **Rançongiciel / fichier supprimé par erreur** : on peut revenir jusqu'a 7 jours en arriere avec les sauvegardes.

Ce que ça couvre pas :
- si quelqu'un vole la cle SSH d'un admin ET son mot de passe, il est root.
- les sauvegardes sont sur la meme machine, si la VM est detruite on perd tout (il faudrait la regle 3-2-1).
- fail2ban sert a rien si l'attaquant change d'IP.
- si il y a une faille dans SSH, le port 22 est ouvert.
- analyse_logs.sh previent personne tout seul, il faut le lancer.

## 4. Procedure de restauration

On restaure d'abord dans un autre dossier pour pas ecraser l'original si ça se passe mal.

1. Voir les versions :
```
sudo ls /sauvegardes/versions
```
2. Prendre la version d'avant le probleme (ex : 2026-11-22_15-54-12) et copier le fichier dans un dossier de test avec ses droits et ses ACL :
```
sudo mkdir -p /root/restauration
sudo rsync -aA /sauvegardes/versions/2026-11-22_15-54-12/srv/projets/test_b4.txt /root/restauration/
```
3. Verifier :
```
sudo cat /root/restauration/test_b4.txt
sudo getfacl /root/restauration/test_b4.txt
```
4. Si c'est bon on le remet a sa place :
```
sudo rsync -aA /root/restauration/test_b4.txt /srv/projets/
```

Test fait le 22/11 sur la VM : on a créé /srv/projets/test_b4.txt avec "version1", fait une sauvegarde, supprimé le fichier puis restauré. Le fichier contenait bien "version1" et les ACL etaient toujours là (group:dev:rwx, group:design:r-x).
