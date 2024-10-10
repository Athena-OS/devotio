# Devotio
Devotio is a secure disk erasure tool based on **DoD  5220.22  M**, **ATA Secure Erase** and **encryption-based destruction**.

It allows to select the specific device to erase or every disk on your system. It involves:
* HDD
* SSD
* LUKS
* USB
* RAM
* Zram
* Swap

The term [Devotio](https://en.wikipedia.org/wiki/Devotio), in Ancient Roman religion, was an extreme form of votum in which a Roman general vowed to sacrifice his own life in battle along with the enemy to chthonic gods in exchange for a victory.

## Requirements

Arch Linux runtime dependencies:
```
util-linux coreutils e2fsprogs cryptsetup hdparm openssl wipe
```

## Run 
```
sudo bash -c "$(curl -FsSL https://raw.githubusercontent.com/Athena-OS/devotio/refs/heads/main/devotio.sh)"
```

## Bibliography

[Wiping Techniques and Antiforensic Methods](https://www.researchgate.net/publication/328834436_Wiping_Techniques_and_Anti-Forensics_Methods)
