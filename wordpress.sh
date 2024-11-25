#!/bin/bash

# Función para verificar si MySQL o MariaDB están instalados
verificar_db() {
    if command -v mysql >/dev/null 2>&1; then
        DB_INSTALLED="mysql"
    elif command -v mariadb >/dev/null 2>&1; then
        DB_INSTALLED="mariadb"
    else
        dialog --yesno "No se ha detectado ningún sistema de base de datos. ¿Deseas instalar MariaDB?" 8 40
        if [ $? -eq 0 ]; then
            DB_INSTALLED="mariadb"
            sudo apt update && sudo apt install -y mariadb-server
        else
            dialog --msgbox "Es necesario instalar un sistema de base de datos para continuar." 6 40
            exit 1
        fi
    fi
}

# Función para seleccionar el sistema de base de datos si no está instalado
seleccionar_db() {
    DB_OPTION=$(dialog --menu "Selecciona el sistema de base de datos (si tienes ambos, selecciona el que prefieras):" 15 50 2 \
        1 "MySQL" \
        2 "MariaDB" 3>&1 1>&2 2>&3)

    case $DB_OPTION in
        1)
            DB_TYPE="mysql"
            ;;
        2)
            DB_TYPE="mariadb"
            ;;
        *)
            dialog --msgbox "Opción no válida." 6 30
            exit 1
            ;;
    esac
}

# Función para instalar dependencias
instalar_dependencias() {
    dialog --infobox "Instalando dependencias..." 6 40
    sleep 2  # Esperar 2 segundos para que el mensaje sea visible
    sudo apt update
    if [ "$DB_INSTALLED" == "mysql" ] || [ "$DB_TYPE" == "mysql" ]; then
        sudo apt install -y apache2 mysql-server php php-mysql libapache2-mod-php php-xml php-curl php-zip php-gd
    else
        sudo apt install -y apache2 mariadb-server php php-mysql libapache2-mod-php php-xml php-curl php-zip php-gd
    fi
}

# Función para configurar la base de datos
configurar_base_datos() {
    DB_NAME=$(dialog --inputbox "Introduce el nombre de la base de datos:" 8 40 3>&1 1>&2 2>&3)
    DB_USER=$(dialog --inputbox "Introduce el nombre de usuario de la base de datos:" 8 40 3>&1 1>&2 2>&3)
if [[ ! "$DB_NAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
    dialog --msgbox "El nombre de la base de datos solo puede contener letras, números y guiones bajos." 6 50
    exit 1
fi
    # Solicitar la contraseña dos veces
    while true; do
        DB_PASS=$(dialog --passwordbox "Introduce la contraseña del usuario:" 8 40 3>&1 1>&2 2>&3)
        DB_PASS_CONFIRM=$(dialog --passwordbox "Confirma la contraseña:" 8 40 3>&1 1>&2 2>&3)

        if [ "$DB_PASS" == "$DB_PASS_CONFIRM" ]; then
            break
        else
            dialog --msgbox "Las contraseñas no coinciden. Inténtalo de nuevo." 6 40
        fi
    done

    dialog --infobox "Configurando la base de datos..." 6 40
    sleep 2  # Esperar 2 segundos para que el mensaje sea visible

    if [ "$DB_INSTALLED" == "mysql" ] || [ "$DB_TYPE" == "mysql" ]; then
        sudo mysql -e "CREATE DATABASE $DB_NAME;"
        sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
        sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
        sudo mysql -e "FLUSH PRIVILEGES;"
    else
        sudo mariadb -e "CREATE DATABASE $DB_NAME;"
        sudo mariadb -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
        sudo mariadb -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
        sudo mariadb -e "FLUSH PRIVILEGES;"
    fi
}

# Función para descargar WordPress
descargar_wordpress() {
    dialog --infobox "Descargando WordPress..." 6 40
    sleep 2  # Esperar 2 segundos para que el mensaje sea visible
    wget -q https://wordpress.org/latest.tar.gz

    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Error al descargar WordPress. Verifica tu conexión a Internet." 6 40
        exit 1
    fi

    dialog --infobox "Descomprimiendo WordPress..." 6 40
    sleep 2  # Esperar 2 segundos para que el mensaje sea visible
    tar -xzf latest.tar.gz
    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Error al descomprimir WordPress." 6 40
        exit 1
    fi

    dialog --infobox "Moviendo archivos de WordPress a /var/www/wordpress/" 6 40
    sleep 2  # Esperar 2 segundos para que el mensaje sea visible
    sudo mkdir -p /var/www/wordpress
    sudo mv wordpress/* /var/www/wordpress/
    sudo chown -R www-data:www-data /var/www/wordpress/
    sudo chmod -R 755 /var/www/wordpress/
    
    rm -rf wordpress latest.tar.gz
}

# Función para configurar Apache y generar SSL
configurar_apache_ssl() {
    DOMAIN=$(dialog --inputbox "Introduce tu dominio (ejemplo.com):" 8 40 3>&1 1>&2 2>&3)
    EMAIL=$(dialog --inputbox "Introduce tu correo electrónico para certbot (necesario para el certificado SSL):" 8 40 3>&1 1>&2 2>&3)

    # Configuración del VirtualHost
    sudo bash -c "cat > /etc/apache2/sites-available/wordpress.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot /var/www/wordpress

    <Directory /var/www/wordpress>
        AllowOverride All
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF"

    sudo a2ensite wordpress.conf
    sudo a2dissite 000-default.conf
    sudo systemctl restart apache2

    # Instalar certbot y obtener certificado SSL
    sudo apt install -y certbot python3-certbot-apache
    sudo certbot --apache -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email
}

# Función para finalizar la instalación
finalizar_instalacion() {
    dialog --msgbox "Instalación completa. Accede a tu sitio en: https://$DOMAIN" 8 60
    dialog --msgbox "Recuerda los siguientes datos para configurar WordPress:\nNombre de la base de datos: $DB_NAME\nUsuario de la base de datos: $DB_USER\nContraseña del usuario: $DB_PASS" 10 60
}

# Comenzar instalación de WordPress
verificar_db
seleccionar_db
instalar_dependencias
configurar_base_datos
descargar_wordpress
configurar_apache_ssl
finalizar_instalacion
