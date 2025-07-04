#!/bin/bash
# vLEI Environment variables for KERIA and KLI
# Separated to dedicated file to make debugging from multiple terminal sessions easier.

export CONFIG_DIR=./config
export INIT_CFG=habery-config.json
export WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
export WIT_HOST=http://127.0.0.1:5642
export SCHEMA_SERVER=http://127.0.0.1:7723
export KERIA_SERVER=http://127.0.0.1:3903

export LE_LEI=254900OPPU84GM83MG36 # GLEIF Americas

# GEDA AIDs - GLEIF External Delegated AID
export GAR1=accolon
export GAR1_PRE=ENFbr9MI0K7f4Wz34z4hbzHmCTxIPHR9Q_gWjLJiv20h
export GAR1_SALT=0AA2-S2YS4KqvlSzO7faIEpH
export GAR1_PASSCODE=18b2c88fd050851c45c67

export GAR2=bedivere
export GAR2_PRE=EJ7F9XcRW85_S-6F2HIUgXcIcywAy0Nv-GilEBSRnicR
export GAR2_SALT=0ADD292rR7WEU4GPpaYK4Z6h
export GAR2_PASSCODE=b26ef3dd5c85f67c51be8

export GEDA_NAME=dagonet
export GEDA_PRE=EMCRBKH4Kvj03xbEVzKmOIrg0sosqHUF9VG2vzT9ybzv

# Legal Entity AIDs
export LAR1=elaine
export LAR1_PRE=ELTDtBrcFsHTMpfYHIJFvuH6awXY1rKq4w6TBlGyucoF
export LAR1_SALT=0AB90ainJghoJa8BzFmGiEWa
export LAR1_PASSCODE=tcc6Yj4JM8MfTDs1IiidP

export LAR2=finn
export LAR2_PRE=EBpwQouCaOlglS6gYo0uD0zLbuAto5sUyy7AK9_O0aI1
export LAR2_SALT=0AA4m2NxBxn0w5mM9oZR2kHz
export LAR2_PASSCODE=2pNNtRkSx8jFd7HWlikcg

export LE_NAME=gareth
export LE_PRE=EBsmQ6zMqopxMWhfZ27qXVpRKIsRNKbTS_aXMtWt67eb


# QAR AIDs - filled in later after KERIA setup
export QAR1=galahad
export QAR1_PRE=
export QAR1_SALT=0ACgCmChLaw_qsLycbqBoxDK

export QAR2=lancelot
export QAR2_PRE=
export QAR2_SALT=0ACaYJJv0ERQmy7xUfKgR6a4

export QAR3=tristan
export QAR3_SALT=0AAzX0tS638c9SEf5LnxTlj4

export QVI_NAME=percival
export QVI_PRE=

# Person AID
export PERSON_NAME="Mordred Delacqs"
export PERSON=mordred
export PERSON_PRE=
export PERSON_SALT=0ABlXAYDE2TkaNDk4UXxxtaN
export PERSON_ECR="Consultant"
export PERSON_OOR="Advisor"


# Sally - vLEI Reporting API
export WEBHOOK_HOST=http://127.0.0.1:9923
export SALLY_HOST=http://127.0.0.1:9723
export SALLY=sally
export SALLY_PASSCODE=VVmRdBTe5YCyLMmYRqTAi
export SALLY_SALT=0AD45YWdzWSwNREuAoitH_CC
export SALLY_PRE=EHLWiN8Q617zXqb4Se4KfEGteHbn_way2VG5mcHYh5bm

# Registries
export GEDA_REGISTRY=vLEI-external
export LE_REGISTRY=vLEI-internal
export QVI_REGISTRY=vLEI-qvi

# Credentials
export QVI_SCHEMA=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
export LE_SCHEMA=ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY
export ECR_AUTH_SCHEMA=EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g
export OOR_AUTH_SCHEMA=EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E
export ECR_SCHEMA=EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw
export OOR_SCHEMA=EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy