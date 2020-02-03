#!/bin/bash
#
# Autor: Daniel Araújo Chaves Souza
# Created date: 30 de janeiro de 2020
# Last Updated: 03 de fevereiro de 2020
# Version: 1.1
#

# Função para encerrar script
encerrar() {
	# Define assunto do E-mail
	if cat "$LOG_PATH" | grep -q "ERRO";then
		local ASSUNTO="Erro no Backup - $XSNAME"
	else
		local ASSUNTO="Backup Concluído - $XSNAME"
	fi

	# Envia e-mail com os logs
	mail -s "$ASSUNTO" "suporte@cenapad.ufc.br" < "$LOG_PATH"

	# Encerra Script
	exit
}

# Data atual
readonly DATE=`date +%d%b%Y`
# Nome do host
readonly XSNAME=`hostname`
# Arquivo temporario com uuids das vms
readonly UUIDFILE=/tmp/xen-uuids.txt
# IP do storage
readonly STORAGE_IP="200.19.191.15"
# Pasta onde será montado o volume de backup do storage
readonly MOUNTPOINT=/mnt/backup_vms
# Volume de backup do storage
readonly STORAGE_VOL="/vol/backup_vms"
# Diretório onde é armazenado os logs
readonly LOG_DIR="/root/scriptbackup/logs"
# Path para o log
readonly LOG_PATH="$LOG_DIR/log_$DATE"
# Diretorío de backup
readonly BACKUPPATH=${MOUNTPOINT}/${XSNAME}/${DATE}
# Guarda o ano anterior
readonly ANO_ANTERIOR=$((`date +%Y`-1))

# Se o diretório de logs não existir ele é criado
if [ ! -d "$LOG_DIR" ]; then
	mkdir -p "$LOG_DIR"
fi

# Cabeçalho do log
echo "RELATÓRIO DE BACKUP DAS MÁQUINAS VIRTUAIS - `date`" > "$LOG_PATH"
echo "----------------------------------------------------" >> "$LOG_PATH"
echo "" >> "$LOG_PATH"

# Se o ponto de montagem não existir ele é criado
if [ ! -d "$MOUNTPOINT" ]; then
	mkdir -p "$MOUNTPOINT"
fi

# Verifica se o volume já está montado
if ! df -h | grep -q "$MOUNTPOINT"; then
	# Monta o storage
	if mount -vt nfs "$STORAGE_IP":"$STORAGE_VOL" "$MOUNTPOINT" >/dev/null 2>&1; then
		echo "[  OK  ] - Montar volume do storage." >> "$LOG_PATH"
	else
		echo "[ ERRO ] - Montar volume do storage." >> "$LOG_PATH"
		echo "- BACKUP CANCELADO!!" >> "$LOG_PATH"

		# Encerra o Script
		encerrar
	fi
else
	echo "[  OK  ] - Montar volume do storage." >> "$LOG_PATH"
fi

# Remove Backups do Ano anterior
if ls "$MOUNTPOINT/$XSNAME" 2>/dev/null | grep -q "$ANO_ANTERIOR"; then
	echo "foi"
	if rm -rf "$MOUNTPOINT"/"$XSNAME"/*"$ANO_ANTERIOR" >/dev/null 2>&1; then
		echo "[  OK  ] - Remover backup de $ANO_ANTERIOR." >> "$LOG_PATH"
	else
		echo "[ ERRO ] - Remover backup de $ANO_ANTERIOR." >> "$LOG_PATH"
	fi
fi

# Cria o diretório dentro do Storage
if mkdir -p "$BACKUPPATH" >/dev/null 2>&1; then
	echo "[  OK  ] - Criar diretório de backup." >> "$LOG_PATH"
else
	echo "[ ERRO ] - Cria diretório de backup." >> "$LOG_PATH"
	echo "- BACKUP CANCELADO!!" >> "$LOG_PATH"
	# Encerra o Script
	encerrar
fi

# Salva os UUIDs das VMs que estão sendo executadas
UUID_LIST=`xe vm-list is-control-domain=false is-a-snapshot=false power-state=running | grep uuid | cut -d':' -f2 | sed 's/ //g'`
# Verifica não está vazia
if [ ${#UUID_LIST} -le 10 ]; then
	echo "[ ERRO ] - Nenhuma VM ligada foi encontrada para backup." >> "$LOG_PATH"
	echo "----------------------------------------------------" >> "$LOG_PATH"
	# Encerra o Script
	encerrar
else
	# Percorre todas as VMs da lista
	for VM_UUID in ${UUID_LIST// /}; do
		# Busca o nome da VM
		VM_NAME=`xe vm-list uuid="$VM_UUID" | grep name-label | cut -d":" -f2 | sed 's/^ *//g'`

		echo "" >> "$LOG_PATH"
		echo "- Iniciando Backup - $VM_NAME" >> "$LOG_PATH"

		# Cria o snapshot e salva o UUID do snap
		SNAP_UUID=`xe vm-snapshot uuid="$VM_UUID" new-name-label="SNAPSHOT-$VM_UUID-$DATE"`

		# Verifica se o snapshot foi criado
		if [ ${#SNAP_UUID} -le 10 ]; then
			echo "[ ERRO ] - Não foi possível criar snapshot para VM $VM_NAME." >> "$LOG_PATH"
		else
		    # Exclui o template
		    if ! xe template-param-set is-a-template=false ha-always-run=false uuid="$SNAP_UUID" >/dev/null 2>&1; then
		    	echo "[ ERRO ] - Não foi possível remover o template." >> "$LOG_PATH"
		    fi
		    
		    # Exporta a VM para o diretório do storage
		    if xe vm-export vm="$SNAP_UUID" filename="$BACKUPPATH/$VM_NAME-$DATE.xva" >/dev/null 2>&1; then
		    	echo "[  OK  ] - Exportar VM para o diretório do storage." >> "$LOG_PATH"
		    else
		    	echo "[ ERRO ] - Exportar VM para o diretório do storage." >> "$LOG_PATH"
		    fi

		    # Remove o snapshot
		    if xe vm-uninstall uuid="$SNAP_UUID" force=true >/dev/null 2>&1; then
		    	echo "[  OK  ] - Remover snapshot." >> "$LOG_PATH"
		    else
		    	echo "[ ERRO ] - Remover snapshot." >> "$LOG_PATH"
		    fi
		fi
		echo "----------------------------------------------------" >> "$LOG_PATH"
	done
fi

STORAGE_INFO=`df -h "$MOUNTPOINT/$XSNAME/" | grep "$STORAGE_VOL"`
STORAGE_SIZE=`echo "$STORAGE_INFO" | cut -d' ' -f3`
STORAGE_USED=`echo "$STORAGE_INFO" | cut -d' ' -f5`
STORAGE_AVAIL=`echo "$STORAGE_INFO" | cut -d' ' -f7`
STORAGE_USED_P=`echo "$STORAGE_INFO" | cut -d' ' -f10`

echo "" >> "$LOG_PATH"
echo "Storage $STORAGE_IP" >> "$LOG_PATH"
echo "----------------------------------------------------" >> "$LOG_PATH"
echo " - Volume: $STORAGE_VOL" >> "$LOG_PATH"
echo " - Capacidade: $STORAGE_SIZE ($STORAGE_AVAIL livre)" >> "$LOG_PATH"
echo " - Usado: $STORAGE_USED ($STORAGE_USED_P do total)" >> "$LOG_PATH"
echo "----------------------------------------------------" >> "$LOG_PATH"

# Desmonta volume do storage
if umount "$MOUNTPOINT"  >/dev/null 2>&1; then
	echo "[  OK  ] - Desmontar volume do storage." >> "$LOG_PATH"
else
	echo "[ ERRO ] - Desmontar volume do storage." >> "$LOG_PATH"
fi

# Encerra o Script
encerrar