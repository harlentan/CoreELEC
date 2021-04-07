#!/bin/sh

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2018-present Team CoreELEC (https://coreelec.org)

[ -z "$SYSTEM_ROOT" ] && SYSTEM_ROOT=""
[ -z "$BOOT_ROOT" ] && BOOT_ROOT="/flash"
[ -z "$BOOT_PART" ] && BOOT_PART=$(df "$BOOT_ROOT" | tail -1 | awk {' print $1 '})
if [ -z "$BOOT_DISK" ]; then
  case $BOOT_PART in
    /dev/sd[a-z][0-9]*)
      BOOT_DISK=$(echo $BOOT_PART | sed -e "s,[0-9]*,,g")
      ;;
    /dev/mmcblk*)
      BOOT_DISK=$(echo $BOOT_PART | sed -e "s,p[0-9]*,,g")
      ;;
  esac
fi

mount -o rw,remount $BOOT_ROOT

DT_ID=""
SUBDEVICE=""

for arg in $(cat /proc/cmdline); do
  case $arg in
    boot=*)
      boot="${arg#*=}"
      case $boot in
        /dev/mmc*)
          BOOT_UUID="$(blkid $boot | sed 's/.* UUID="//;s/".*//g')"
          ;;
        UUID=*|LABEL=*)
          BOOT_UUID="$(blkid | sed 's/"//g' | grep -m 1 -i " $boot " | sed 's/.* UUID=//;s/ .*//g')"
          ;;
        FOLDER=*)
          BOOT_UUID="$(blkid ${boot#*=} | sed 's/.* UUID="//;s/".*//g')"
          ;;
      esac

      DT_ID=$(sh $SYSTEM_ROOT/usr/bin/dtname)
      MIGRATE_DTB=""
      if [ -n "$DT_ID" ]; then
        SUBDEVICE="Generic"
        # modify DT_ID, SUBDEVICE and MIGRATE_DTB by dtb.conf
        [ -f $SYSTEM_ROOT/usr/bin/convert_dtname ] && . $SYSTEM_ROOT/usr/bin/convert_dtname $DT_ID

        case $DT_ID in
          *odroid_c4*)
            SUBDEVICE="Odroid_C4"
            ;;
          *odroid_hc4*)
            SUBDEVICE="Odroid_HC4"
            ;;
          *lafrite)
            SUBDEVICE="LaFrite"
            ;;
        esac
      fi

      UPDATE_DTB_SOURCE="$SYSTEM_ROOT/usr/share/bootloader/device_trees/$DT_ID.dtb"
      if [ -n "$DT_ID" -a -f "$UPDATE_DTB_SOURCE" ]; then
        echo "Updating device tree with $DT_ID.dtb..."
        case $BOOT_PART in
          /dev/coreelec)
            dd if=/dev/zero of=/dev/dtb bs=256k count=1 status=none
            dd if="$UPDATE_DTB_SOURCE" of=/dev/dtb bs=256k status=none
            rm -f "$BOOT_ROOT/dtb.img" # this should not exist, remove if it does
            ;;
          *)
            cp -f "$UPDATE_DTB_SOURCE" "$BOOT_ROOT/dtb.img"
            ;;
        esac
        [ -n "$MIGRATE_DTB" ] && eval $MIGRATE_DTB
      fi

      for all_dtb in /flash/*.dtb ; do
        if [ -f $all_dtb ]; then
          dtb=$(basename $all_dtb)
          if [ -f $SYSTEM_ROOT/usr/share/bootloader/$dtb ]; then
            echo "Updating $dtb..."
            cp -p $SYSTEM_ROOT/usr/share/bootloader/$dtb $BOOT_ROOT
          fi
        fi
      done
      ;;

    disk=*)
      disk="${arg#*=}"
      case $disk in
        /dev/mmc*)
          DISK_UUID="$(blkid $disk | sed 's/.* UUID="//;s/".*//g')"
          ;;
        UUID=*|LABEL=*)
          DISK_UUID="$(blkid | sed 's/"//g' | grep -m 1 -i " $disk " | sed 's/.* UUID=//;s/ .*//g')"
          ;;
        FOLDER=*)
          DISK_UUID="$(blkid ${disk#*=} | sed 's/.* UUID="//;s/".*//g')"
          ;;
      esac
      ;;
  esac
done

if [ -d $BOOT_ROOT/device_trees ]; then
  echo "Updating device_trees folder..."
  rm $BOOT_ROOT/device_trees/*.dtb
  cp -p $SYSTEM_ROOT/usr/share/bootloader/device_trees/*.dtb $BOOT_ROOT/device_trees/
fi

if [ -f $SYSTEM_ROOT/usr/share/bootloader/${SUBDEVICE}_boot.ini ]; then
  echo "Updating boot.ini with ${SUBDEVICE}_boot.ini..."
  cp -p $SYSTEM_ROOT/usr/share/bootloader/${SUBDEVICE}_boot.ini $BOOT_ROOT/boot.ini
  sed -e "s/@BOOT_UUID@/$BOOT_UUID/" \
      -e "s/@DISK_UUID@/$DISK_UUID/" \
      -i $BOOT_ROOT/boot.ini
fi

if [ -f $SYSTEM_ROOT/usr/share/bootloader/config.ini ]; then
  if [ ! -f $BOOT_ROOT/config.ini ]; then
    echo "Creating config.ini..."
    cp -p $SYSTEM_ROOT/usr/share/bootloader/config.ini $BOOT_ROOT/config.ini
  fi
fi

if [ -f $BOOT_ROOT/dtb.xml ]; then
  if [ -f $SYSTEM_ROOT/usr/lib/coreelec/dtb-xml ]; then
    echo "Updating dtb.img by dtb.xml..."
    LD_LIBRARY_PATH=/usr/lib:$SYSTEM_ROOT/usr/lib $SYSTEM_ROOT/usr/lib/coreelec/dtb-xml -s $SYSTEM_ROOT
  fi
fi

if [ "${SUBDEVICE}" == "Odroid_N2" -o "${SUBDEVICE}" == "Odroid_C4" -o "${SUBDEVICE}" == "Odroid_HC4" ]; then
  if [ -f $SYSTEM_ROOT/usr/share/bootloader/hk-boot-logo-1080.bmp.gz ]; then
    echo "Updating boot logos..."
    cp -p $SYSTEM_ROOT/usr/share/bootloader/hk-boot-logo-1080.bmp.gz $BOOT_ROOT/boot-logo-1080.bmp.gz
  fi
fi

if [ "${SUBDEVICE}" == "LePotato" -o "${SUBDEVICE}" == "LaFrite" ]; then
  if [ -f $SYSTEM_ROOT/usr/share/bootloader/boot-logo-1080.bmp.gz ]; then
    echo "Updating boot logos..."
    cp -p $SYSTEM_ROOT/usr/share/bootloader/boot-logo-1080.bmp.gz $BOOT_ROOT/boot-logo-1080.bmp.gz
  fi
fi

if [ -f $SYSTEM_ROOT/usr/share/bootloader/${SUBDEVICE}_u-boot -a ! -e /dev/env ]; then
  echo "Updating u-boot on: $BOOT_DISK..."
  dd if=$SYSTEM_ROOT/usr/share/bootloader/${SUBDEVICE}_u-boot of=$BOOT_DISK conv=fsync bs=1 count=112 status=none
  dd if=$SYSTEM_ROOT/usr/share/bootloader/${SUBDEVICE}_u-boot of=$BOOT_DISK conv=fsync bs=512 skip=1 seek=1 status=none
fi

if [ -f $BOOT_ROOT/boot.scr ]; then
  if [ -f $SYSTEM_ROOT/usr/share/bootloader/${SUBDEVICE}_chain_u-boot ]; then
    echo "Updating chain loaded u-boot..."
    cp -p $SYSTEM_ROOT/usr/share/bootloader/${SUBDEVICE}_chain_u-boot $BOOT_ROOT/u-boot.bin
  fi
  if [ "${SUBDEVICE}" == "LePotato"  -o "${SUBDEVICE}" == "LaFrite" ]; then
    if [ -f $SYSTEM_ROOT/usr/share/bootloader/libretech_chain_boot ]; then
      echo "Updating boot.scr..."
      cp -p $SYSTEM_ROOT/usr/share/bootloader/libretech_chain_boot $BOOT_ROOT/boot.scr
    fi
  fi
fi

if [ -f $BOOT_ROOT/aml_autoscript ]; then
  if [ -f $SYSTEM_ROOT/usr/share/bootloader/aml_autoscript ]; then
    echo "Updating aml_autoscript..."
    cp -p $SYSTEM_ROOT/usr/share/bootloader/aml_autoscript $BOOT_ROOT
    if [ -e /dev/env ]; then
      mkdir -p /var/lock
      dd if=$BOOT_ROOT/aml_autoscript bs=72 skip=1 status=none | \
      while read line; do
        cmd=$(echo $line | sed -n "s|^setenv \(.*\)|$SYSTEM_ROOT/usr/sbin/fw_setenv -c $SYSTEM_ROOT/etc/fw_env.config \1|gp")
        [ -n "$cmd" ] && eval $cmd
      done
    fi
  fi
  if [ -f $SYSTEM_ROOT/usr/share/bootloader/${SUBDEVICE}_cfgload ]; then
    echo "Updating cfgload..."
    cp -p $SYSTEM_ROOT/usr/share/bootloader/${SUBDEVICE}_cfgload $BOOT_ROOT/cfgload
  fi
  $SYSTEM_ROOT/usr/lib/coreelec/check-bl301
  if [ ${?} = 1 ]; then
    echo "Found custom CoreELEC BL301, running inject_bl301 tool..."
    LD_LIBRARY_PATH=/usr/lib:$SYSTEM_ROOT/usr/lib $SYSTEM_ROOT/usr/sbin/inject_bl301 -s $SYSTEM_ROOT -Y &>/dev/null
  fi
fi

# Phicomm_N1
if [ "${SUBDEVICE}" == "Phicomm_N1" ]; then
  if [ -f $SYSTEM_ROOT/usr/share/bootloader/s905_autoscript ]; then
    echo "Updating s905_autoscript..."
    cp -p $SYSTEM_ROOT/usr/share/bootloader/s905_autoscript $BOOT_ROOT
    sleep 1
  fi

  if [ -f $SYSTEM_ROOT/usr/share/bootloader/uInitrd ]; then
    echo "Updating uInitrd..."
    cp -p $SYSTEM_ROOT/usr/share/bootloader/uInitrd $BOOT_ROOT
    sleep 1
  fi
fi

mount -o ro,remount $BOOT_ROOT

# Leave a hint that we just did an update
echo "UPDATE" > /storage/.config/boot.hint
