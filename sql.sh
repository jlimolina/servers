#!/bin/bash

# Comprobar si MariaDB o MySQL está instalado
if command -v mysql &> /dev/null; then
    DB_TYPE="MySQL"
elif command -v mariadb &> /dev/null; then
    DB_TYPE="MariaDB"
else
    dialog --title "Error" --msgbox "No se encontró MySQL o MariaDB instalados." 7 50
    dialog --yesno "¿Quieres instalar una de estas bases de datos?" 7 50
    INSTALL=$?
    if [[ "$INSTALL" == 0 ]]; then
        DB_OPTION=$(dialog --menu "Elige la base de datos a instalar:" 15 50 2 \
        1 "MariaDB" \
        2 "MySQL" \
        3>&1 1>&2 2>&3)
        if [[ "$DB_OPTION" == "1" ]]; then
            sudo apt update
            sudo apt install mariadb-server -y
        elif [[ "$DB_OPTION" == "2" ]]; then
            sudo apt update
            sudo apt install mysql-server -y
        else
            dialog --title "Error" --msgbox "Opción no válida." 7 50
            exit 1
        fi
    else
        exit 1
    fi
fi

# Función para obtener el estado y tiempo de actividad
function obtener_estado_y_tiempo() {
    if [[ "$DB_TYPE" == "MySQL" ]]; then
        STATUS=$(systemctl is-active mysql)
        UPTIME=$(systemctl show -p ActiveEnterTimestamp mysql | cut -d'=' -f2)
    else
        STATUS=$(systemctl is-active mariadb)
        UPTIME=$(systemctl show -p ActiveEnterTimestamp mariadb | cut -d'=' -f2)
    fi

    # Determinar el mensaje de estado
    if [[ "$STATUS" == "active" ]]; then
        STATUS_MSG="Activo"  # Mensaje para estado activo
        STATUS_COLOR="(Estado: Activo)"
    else
        STATUS_MSG="Inactivo"  # Mensaje para estado inactivo
        STATUS_COLOR="(Estado: Inactivo)"
    fi

    # Calcular el tiempo de actividad
    if [[ -n "$UPTIME" ]]; then
        ACTIVE_TIME=$(date -d "$UPTIME" '+%Y-%m-%d %H:%M:%S')
        HOURS_MINUTES=$(($(date +%s) - $(date -d "$UPTIME" +%s)))
        HOURS=$((HOURS_MINUTES / 3600))
        MINUTES=$(((HOURS_MINUTES % 3600) / 60))
        TIME_MSG="$HOURS horas y $MINUTES minutos."
    else
        TIME_MSG="No disponible"
    fi

    # Retornar el mensaje de estado
    echo "$STATUS_COLOR - Tiempo activo: $TIME_MSG"
}

# Función para mostrar bases de datos
function mostrar_bases_de_datos() {
    databases=$(mysql -e "SHOW DATABASES;" | tail -n +2)
    dialog --title "Bases de Datos" --msgbox "$databases" 15 50
}

# Función para crear base de datos
function crear_base_de_datos() {
    DB_NAME=$(dialog --inputbox "Introduce el nombre de la nueva base de datos:" 8 50 3>&1 1>&2 2>&3)
    if [ -z "$DB_NAME" ]; then
        dialog --title "Error" --msgbox "El nombre de la base de datos no puede estar vacío." 7 50
        return
    fi
    mysql -e "CREATE DATABASE $DB_NAME;" && dialog --title "Éxito" --msgbox "Base de datos '$DB_NAME' creada." 7 50
}

# Función para borrar base de datos
function borrar_base_de_datos() {
    databases=($(mysql -e "SHOW DATABASES;" | tail -n +2))

    if [ ${#databases[@]} -eq 0 ]; then
        dialog --title "Error" --msgbox "No se encontraron bases de datos." 7 50
        return
    fi

    # Ajustar la altura del cuadro de diálogo dinámicamente según el número de bases de datos
    height=$((${#databases[@]} + 7))
    if [ $height -gt 20 ]; then height=20; fi  # Límite máximo de 20 líneas visibles

    # Crear el menú en una lista continua
    db_list=()
    for db in "${databases[@]}"; do
        db_list+=("$db" "")  # Opción y descripción vacía para evitar duplicados
    done

    DB_NAME=$(dialog --menu "Selecciona la base de datos a borrar:" $height 50 ${#databases[@]} "${db_list[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$DB_NAME" ]; then
        return
    fi

    # Confirmación para borrar
    dialog --title "Confirmación" --yesno "¿Estás seguro de que deseas borrar la base de datos '$DB_NAME'? Esta acción es irreversible." 7 60
    if [ $? -eq 0 ]; then
        mysql -e "DROP DATABASE $DB_NAME;" && dialog --title "Éxito" --msgbox "Base de datos '$DB_NAME' borrada." 7 50
    fi
}

# Función para hacer copia de seguridad de una base de datos
function hacer_copia_de_seguridad() {
    databases=($(mysql -e "SHOW DATABASES;" | tail -n +2))

    if [ ${#databases[@]} -eq 0 ]; then
        dialog --title "Error" --msgbox "No se encontraron bases de datos." 7 50
        return
    fi

    height=$((${#databases[@]} + 7))
    if [ $height -gt 20 ]; then height=20; fi

    db_list=()
    for db in "${databases[@]}"; do
        db_list+=("$db" "")
    done

    DB_NAME=$(dialog --menu "Selecciona la base de datos para hacer una copia de seguridad:" $height 50 ${#databases[@]} "${db_list[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$DB_NAME" ]; then
        return
    fi

    BACKUP_FILE="${DB_NAME}_$(date +%F).sql"

    # Usar sudo para mysqldump con usuario root
    sudo mysqldump -u root "$DB_NAME" > "$BACKUP_FILE" && dialog --title "Éxito" --msgbox "Copia de seguridad guardada en '$BACKUP_FILE'." 7 50
}

# Función para crear usuario
function crear_usuario() {
    DB_USER=$(dialog --inputbox "Introduce el nombre del nuevo usuario:" 8 50 3>&1 1>&2 2>&3)
    if [ -z "$DB_USER" ]; then
        dialog --title "Error" --msgbox "El nombre del usuario no puede estar vacío." 7 50
        return
    fi
    DB_PASS=$(dialog --passwordbox "Introduce la contraseña para el usuario:" 8 50 3>&1 1>&2 2>&3)
    if [ -z "$DB_PASS" ]; then
        dialog --title "Error" --msgbox "La contraseña no puede estar vacía." 7 50
        return
    fi
    mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" && dialog --title "Éxito" --msgbox "Usuario '$DB_USER' creado." 7 50
}

# Función para borrar usuario
function borrar_usuario() {
    usuarios=($(mysql -e "SELECT User FROM mysql.user;" | tail -n +2))

    if [ ${#usuarios[@]} -eq 0 ]; then
        dialog --title "Error" --msgbox "No se encontraron usuarios." 7 50
        return
    fi

    height=$((${#usuarios[@]} + 7))
    if [ $height -gt 20 ]; then height=20; fi

    user_list=()
    for user in "${usuarios[@]}"; do
        user_list+=("$user" "")
    done

    DB_USER=$(dialog --menu "Selecciona el usuario a borrar:" $height 50 ${#usuarios[@]} "${user_list[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$DB_USER" ]; then
        return
    fi

    # Confirmación para borrar
    dialog --title "Confirmación" --yesno "¿Estás seguro de que deseas borrar el usuario '$DB_USER'? Esta acción es irreversible." 7 60
    if [ $? -eq 0 ]; then
        mysql -e "DROP USER '$DB_USER'@'localhost';" && dialog --title "Éxito" --msgbox "Usuario '$DB_USER' borrado." 7 50
    fi
}

# Función para mostrar usuarios con las bases de datos a las que tienen acceso
function mostrar_usuarios_con_bases_de_datos() {
    # Obtener la lista de usuarios
    usuarios=($(mysql -e "SELECT User FROM mysql.user;" | tail -n +2))
    
    # Comprobar si existen usuarios
    if [ ${#usuarios[@]} -eq 0 ]; then
        dialog --title "Error" --msgbox "No se encontraron usuarios." 7 50
        return
    fi

    # Variable para almacenar los permisos de todos los usuarios
    permisos=""

    # Iterar sobre cada usuario y mostrar las bases de datos a las que tiene acceso
    for user in "${usuarios[@]}"; do
        # Obtener los permisos del usuario
        grants=$(mysql -e "SHOW GRANTS FOR '$user'@'localhost';")
        
        # Filtrar las bases de datos de los permisos (ignoramos los permisos globales '*.*')
        bases_de_datos=$(echo "$grants" | grep -oP "(ON \K[^ ]+(?=\.\*))" | grep -v '\*')

        # Verificar si se encontró alguna base de datos específica
        if [ -n "$bases_de_datos" ]; then
            # Si hay bases de datos específicas, las mostramos
            permisos+="Usuario: $user\nBases de datos:\n$bases_de_datos\n\n"
        else
            # Si no tiene acceso específico a ninguna base de datos, se indica "Ninguno"
            permisos+="Usuario: $user\nBases de datos: Ninguno\n\n"
        fi
    done

    # Mostrar la información en un cuadro de diálogo
    dialog --title "Usuarios y Bases de Datos" --msgbox "$permisos" 20 70
}



# Función para dar permisos a un usuario
function dar_permisos_a_usuario() {
    usuarios=($(mysql -e "SELECT User FROM mysql.user;" | tail -n +2))
    databases=($(mysql -e "SHOW DATABASES;" | tail -n +2))

    if [ ${#usuarios[@]} -eq 0 ]; then
        dialog --title "Error" --msgbox "No se encontraron usuarios." 7 50
        return
    fi

    if [ ${#databases[@]} -eq 0 ]; then
        dialog --title "Error" --msgbox "No se encontraron bases de datos." 7 50
        return
    fi

    height=$((${#usuarios[@]} + ${#databases[@]} + 7))
    if [ $height -gt 20 ]; then height=20; fi

    user_list=()
    for user in "${usuarios[@]}"; do
        user_list+=("$user" "")
    done

    DB_USER=$(dialog --menu "Selecciona el usuario al que dar permisos:" $height 50 ${#usuarios[@]} "${user_list[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$DB_USER" ]; then
        return
    fi

    # Listar bases de datos para otorgar permisos
    db_list=()
    for db in "${databases[@]}"; do
        db_list+=("$db" "")
    done

    DB_NAME=$(dialog --menu "Selecciona la base de datos para otorgar permisos:" $height 50 ${#databases[@]} "${db_list[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$DB_NAME" ]; then
        return
    fi

    # Otorgar permisos por defecto: ALL PRIVILEGES
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" && dialog --title "Éxito" --msgbox "Permisos otorgados al usuario '$DB_USER' en la base de datos '$DB_NAME'." 7 50
}

# Función principal para mostrar el menú
function mostrar_menu() {
    while true; do
        ESTADO_Y_TIEMPO=$(obtener_estado_y_tiempo)
        OPCION=$(dialog --menu "Gestión de Bases de Datos ($DB_TYPE) - $ESTADO_Y_TIEMPO" 20 60 12 \
         "" "-- Bases de Datos --" \
        1 "Crear base de datos" \
        2 "Borrar base de datos" \
        3 "Mostrar bases de datos" \
        4 "Backup de base de datos" \
          "" "-- Usuarios --" \
        5 "Crear usuario" \
        6 "Borrar usuario" \
        7 "Mostrar usuarios y permisos" \
        8 "Dar permisos a usuario" \
        9 "Menú principal" \
        10 "Salir" \
        3>&1 1>&2 2>&3)

        case $OPCION in
            1) crear_base_de_datos ;;
            2) borrar_base_de_datos ;;
            3) mostrar_bases_de_datos ;;
            4) hacer_copia_de_seguridad ;;
            5) crear_usuario ;;
            6) borrar_usuario ;;
            7) mostrar_usuarios_con_bases_de_datos ;;
            8) dar_permisos_a_usuario ;;
            9) bash apps.sh ;;
            10) break ;;
            *) dialog --title "Error" --msgbox "Opción no válida." 7 50 ;;
        esac
    done
}

# Ejecutar el menú principal
mostrar_menu
