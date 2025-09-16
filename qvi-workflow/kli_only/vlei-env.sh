#!/bin/bash
# vLEI Environment variables
# Separated to dedicated file to make debugging from multiple terminal sessions easier.

export CONFIG_DIR=./config
export INIT_CFG=common-habery-config.json
export WAN_PRE=BBilc4-L3tFUnfM_wJr4S4OJanAv_VmF_dJNN6vkf2Ha
export WIT_HOST=http://127.0.0.1:5642
export SCHEMA_SERVER=http://127.0.0.1:7723

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

# QAR AIDs
export QAR1=galahad
export QAR1_PRE=ELPwNB8R_CsMNHw_amyp-xnLvpxxTgREjEIvc7oJgqfW
export QAR1_SALT=0ACgCmChLaw_qsLycbqBoxDK
export QAR1_PASSCODE=e6b3402845de8185abe94

export QAR2=lancelot
export QAR2_PRE=ENlxz3lZXjEo73a-JBrW1eL8nxSWyLU49-VkuqQZKMtt
export QAR2_SALT=0ACaYJJv0ERQmy7xUfKgR6a4
export QAR2_PASSCODE=bdf1565a750ff3f76e4fc

export QVI_NAME=percival
export QVI_PRE=EAwP4xBP4C8KzoKCYV2e6767OTnmR5Bt8zmwhUJr9jHh

# Legal Entity AIDs
export LAR1=elaine
export LAR1_PRE=ELTDtBrcFsHTMpfYHIJFvuH6awXY1rKq4w6TBlGyucoF
export LAR1_SALT=0AB90ainJghoJa8BzFmGiEWa
export LAR1_PASSCODE=tcc6Yj4JM8MfTDs1IiidP

export LAR2=finn
export LAR2_PRE=EBpwQouCaOlglS6gYo0uD0zLbuAto5sUyy7AK9_O0aI1
export LAR2_SALT=0AA4m2NxBxn0w5mM9oZR2kHz
export LAR2_PASSCODE=2pNNtRkSx8jFd7HWlikcg

export LE_MS_NAME=gareth
export LE_MS_PRE=EBsmQ6zMqopxMWhfZ27qXVpRKIsRNKbTS_aXMtWt67eb

# Person AID
export PERSON_NAME="Mordred Delacqs"
export PERSON=mordred
export PERSON_PRE=EIV2RRWifgojIlyX1CyEIJEppNzNKTidpOI7jYnpycne
export PERSON_SALT=0ABlXAYDE2TkaNDk4UXxxtaN
export PERSON_PASSCODE=c4479ae785625c8e50a7e
export PERSON_ECR="Consultant"
export PERSON_OOR="Advisor"

# Sally - vLEI Reporting API
export SALLY=sally-indirect
export SALLY_PASSCODE=VVmRdBTe5YCyLMmYRqTAi
export SALLY_SALT=0AD45YWdzWSwNREuAoitH_CC
export SALLY_PRE=ECu-Lt62sUHkdZPnhIBoSuQrJWbi4Rqf_xUBOOJqAR7K

# Registries
export GEDA_REGISTRY=vLEI-external
export QVI_REGISTRY=vLEI-qvi
export LE_REGISTRY=vLEI-internal

# Credentials
export QVI_SCHEMA=EBfdlu8R27Fbx-ehrqwImnK-8Cm79sqbAQ4MmvEAYqao
export LE_SCHEMA=ENPXp1vQzRF6JwIuS-mp2U8Uf1MoADoP_GqQ62VsDZWY
export OOR_AUTH_SCHEMA=EKA57bKBKxr_kN7iN5i7lMUxpMG-s19dRcmov1iDxz-E
export ECR_AUTH_SCHEMA=EH6ekLjSr8V32WyFbGe1zXjTzFs9PkTYmupJ9H65O14g
export OOR_SCHEMA=EBNaNu-M9P5cgrnfl2Fvymy4E_jvxxyjb70PRtiANlJy
export ECR_SCHEMA=EEy9PkikFcANV1l7EHukCeXqrzT1hNZjGlUk7wuMO5jw

export SALLY_HOST=http://127.0.0.1:9723