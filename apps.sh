#!/bin/bash
if [ "$EUID" -ne 0 ]; then
    echo "Este script debe ejecutarse como root." >&2
    exit 1
fi
for cmd in tar awk df; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "El comando '$cmd' no está instalado. Por favor, instálalo primero." >&2
        exit 1
    fi
done
# Verificar si el paquete dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "El paquete 'dialog' no está instalado. Instalando..."
    apt-get update && apt-get install -y dialog
fi

# Función para obtener las métricas del sistema
obtener_metricas() {
    UPTIME=$(uptime -p)  # Tiempo encendido
    DISK_AVAILABLE=$(df -h / | awk 'NR==2 {print $4}')  # Espacio disponible en la raíz
    MEMORY_USAGE=$(free -h | awk 'NR==2 {print $3 " / " $2}')  # Uso de memoria RAM

    # Comprobar si Apache está activo
    if systemctl is-active --quiet apache2; then
        APACHE_STATUS="Activo"
    else
        APACHE_STATUS="Inactivo"
    fi

    METRICS="Tiempo encendido: $UPTIME\n"
    METRICS+="Espacio disponible en disco: $DISK_AVAILABLE\n"
    METRICS+="Uso de memoria RAM: $MEMORY_USAGE\n"
    METRICS+="Estado de Apache: $APACHE_STATUS"
}

# Función para mostrar el submenú de instalación
mostrar_menu_instalacion() {
    while true; do
        INSTALL_OPTION=$(dialog --menu "Instalar Aplicaciones" 15 50 4 \
            "WordPress" "" \
            "PrestaShop" "" \
            "Moodle" "" \
            "Matomo" "" \
            "PhpBB"  "" \
            "Mastodon" "" \
            "Regresar" "" 3>&1 1>&2 2>&3)

        case $? in
            0)  # El usuario seleccionó OK
                case $INSTALL_OPTION in
                    "WordPress")
                        bash wordpress.sh  # Llama al script de instalación de WordPress
                        ;;
                    "PrestaShop")
                        bash prestashop.sh
                         ;;
                    "Moodle")
                        bash moodle.sh
                        ;;
                    "Matomo")
                        bash matomo.sh
                        ;;
                    "PhpBB")
                        bash phpbb.sh
                        ;;
                    "Mastodon")
                        bash mastodon.sh 
                        ;;   
                    "Regresar")
                        break
                        ;;
                    *)
                        dialog --msgbox "Opción no válida." 6 30
                        ;;
                esac
                ;;
            1)  # El usuario seleccionó Cancel
                break
                ;;
            255)  # El usuario cerró la ventana de diálogo
                break
                ;;
        esac
    done
}

# Función para borrar un servidor
borrar_servidor() {
    SERVIDORES=$(ls -d /var/www/*/ | grep -v "/var/www/html/" | xargs -n 1 basename)

    if [ -z "$SERVIDORES" ]; then
        dialog --msgbox "No se encontraron servidores instalados." 6 40
    else
        # Crear un array en el formato de pares: opción y descripción
        OPCIONES_SERVIDORES=()
        for SERVIDOR in $SERVIDORES; do
            OPCIONES_SERVIDORES+=("$SERVIDOR" "$SERVIDOR")  # Añadir el servidor como opción y descripción
        done

        # Mostrar el menú para seleccionar un servidor a borrar
        SERVIDOR=$(dialog --menu "Selecciona el servidor a borrar:" 15 50 6 "${OPCIONES_SERVIDORES[@]}" 3>&1 1>&2 2>&3)

        if [ -n "$SERVIDOR" ]; then
            dialog --yesno "¿Estás seguro de que quieres borrar el servidor $SERVIDOR?" 7 50
            if [ $? -eq 0 ]; then
                rm -rf "/var/www/$SERVIDOR"
                rm "/etc/apache2/sites-available/$SERVIDOR.conf"
                systemctl reload apache2
                dialog --msgbox "Servidor $SERVIDOR eliminado." 6 40
            fi
        fi
    fi
}
# Función para realizar un backup de un servidor
realizar_backup() {
    # Obtener la lista de servidores en /var/www/ (excluyendo el directorio html)
    SERVIDORES=$(ls -d /var/www/*/ | grep -v "/var/www/html/" | xargs -n 1 basename)

    if [ -z "$SERVIDORES" ]; then
        dialog --msgbox "No se encontraron servidores instalados." 6 40
    else
        # Crear un array con opciones para seleccionar
        OPCIONES_SERVIDORES=()
        for SERVIDOR in $SERVIDORES; do
            OPCIONES_SERVIDORES+=("$SERVIDOR" "$SERVIDOR")  # Añadir el servidor como opción
        done

        # Mostrar el menú para seleccionar un servidor a hacer backup
        SERVIDOR=$(dialog --menu "Selecciona el servidor a respaldar:" 15 50 6 "${OPCIONES_SERVIDORES[@]}" 3>&1 1>&2 2>&3)

        if [ -n "$SERVIDOR" ]; then
            BACKUP_DIR=$(pwd)  # Directorio donde se almacenará el backup
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)  # Añadir timestamp para backups únicos
            BACKUP_FILE="$BACKUP_DIR/${SERVIDOR}_backup_$TIMESTAMP.tar.gz"

            dialog --infobox "Realizando copia de seguridad del servidor $SERVIDOR..." 5 50
            # Crear un tar.gz de la carpeta seleccionada y copiarlo al directorio actual
            tar -czvf "$BACKUP_FILE" "/var/www/$SERVIDOR" || error_exit "Error al crear el backup del servidor $SERVIDOR."

            dialog --msgbox "Backup del servidor $SERVIDOR completado.\nArchivo creado: $BACKUP_FILE" 8 50
        else
            dialog --msgbox "No se seleccionó ningún servidor." 6 40
        fi
    fi
}

# Función para listar servidores
listar_servidores() {
    SERVIDORES=$(ls -d /var/www/*/ | grep -v "/var/www/html/" | xargs -n 1 basename)
    if [ -z "$SERVIDORES" ]; then
        dialog --msgbox "No se encontraron servidores instalados." 6 40
    else
        dialog --msgbox "Servidores instalados:\n$SERVIDORES" 15 50
    fi
}

# Función para mostrar el menú principal con las métricas en la parte superior
mostrar_menu_principal() {
    while true; do
        obtener_metricas  # Obtener las métricas actualizadas

        MENU_OPTION=$(dialog --menu "$METRICS" 20 70 6 \
            "Instalar Servidor" "" \
            "Borrar Servidor" "" \
            "Lista de Servidores" "" \
            "Copia de Seguridad" "" \
            "Gestión de Base de Datos" "" \
            "Salir" "" 3>&1 1>&2 2>&3)

        case $? in
            0)  # El usuario seleccionó OK
                case $MENU_OPTION in
                    "Instalar Servidor")
                        mostrar_menu_instalacion
                        ;;
                    "Borrar Servidor")
                        borrar_servidor
                        ;;
                    "Lista de Servidores")
                        listar_servidores
                        ;;
                    "Copia de Seguridad")
                        realizar_backup
                        ;;
                    "Gestión de Base de Datos")
                        bash sql.sh
                        ;;
                    "Salir")
                        break
                        ;;
                    *)
                        dialog --msgbox "Opción no válida." 6 30
                        ;;
                esac
                ;;
            1)  # El usuario seleccionó Cancel
                break
                ;;
            255)  # El usuario cerró la ventana de diálogo
                break
                ;;
        esac
    done
}

# Comenzar el script mostrando el menú principal
mostrar_menu_principal
