#!/bin/bash

# Función para mostrar mensajes de error y salir
error_exit() {
    dialog --msgbox "$1" 8 40
    exit 1
}

# Función para verificar si MySQL o MariaDB ya están instalados
verificar_db_instalada() {
    if command -v mysql &> /dev/null; then
        MYSQL_VERSION=$(mysql --version)
        dialog --msgbox "MySQL ya está instalado: $MYSQL_VERSION. No se instalará otra base de datos." 8 40
        DB_TYPE="mysql"
    elif command -v mariadb &> /dev/null; then
        MARIADB_VERSION=$(mariadb --version)
        dialog --msgbox "MariaDB ya está instalado: $MARIADB_VERSION. No se instalará otra base de datos." 8 40
        DB_TYPE="mariadb"
    else
        seleccionar_db
    fi
}

# Función para seleccionar la base de datos en caso de que ninguna esté instalada
seleccionar_db() {
    DB_OPTION=$(dialog --menu "Selecciona el sistema de base de datos:" 15 50 2 \
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

# Función para instalar la base de datos
instalar_base_datos() {
    if [ "$DB_TYPE" == "mysql" ]; then
        dialog --infobox "Instalando MySQL..." 6 40
        sudo apt-get install -y mysql-server || error_exit "Error al instalar MySQL."
    elif [ "$DB_TYPE" == "mariadb" ]; then
        dialog --infobox "Instalando MariaDB..." 6 40
        sudo apt-get install -y mariadb-server || error_exit "Error al instalar MariaDB."
    fi
}

# Función para recopilar datos del usuario
recopilar_datos_usuario() {
    DB_NAME=$(dialog --inputbox "Ingrese el nombre de la base de datos para Matomo:" 8 40 3>&1 1>&2 2>&3)
    DB_USER=$(dialog --inputbox "Ingrese el nombre de usuario de la base de datos:" 8 40 3>&1 1>&2 2>&3)
    DB_PASSWORD=$(dialog --passwordbox "Ingrese la contraseña del usuario de la base de datos:" 8 40 3>&1 1>&2 2>&3)
    DB_HOST=$(dialog --inputbox "Ingrese el host de la base de datos (por defecto: localhost):" 8 40 "localhost" 3>&1 1>&2 2>&3)
    DOMAIN=$(dialog --inputbox "Ingrese el dominio para su instalación de Matomo (ej. ejemplo.com):" 8 40 3>&1 1>&2 2>&3)
    EMAIL=$(dialog --inputbox "Ingrese su correo electrónico para el certificado SSL:" 8 40 3>&1 1>&2 2>&3)

    if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DB_HOST" ] || [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
        error_exit "Todos los campos son obligatorios. La instalación se cancelará."
    fi
}

# Función para instalar dependencias necesarias
instalar_dependencias() {
    dialog --infobox "Instalando dependencias necesarias..." 5 40
    sudo apt-get update && sudo apt-get install -y apache2 php php-mysql libapache2-mod-php php-xml php-mbstring php-gd unzip || error_exit "Error al instalar las dependencias."
}

# Función para descargar e instalar Matomo
instalar_matomo() {
    dialog --infobox "Descargando Matomo..." 5 40
    wget https://builds.matomo.org/matomo-latest.zip || error_exit "Error al descargar Matomo."

    dialog --infobox "Descomprimiendo Matomo..." 5 40
    unzip matomo-latest.zip -d /var/www/ || error_exit "Error al descomprimir Matomo."
    sudo chown -R www-data:www-data /var/www/matomo
    sudo chmod -R 755 /var/www/matomo
    rm matomo-latest.zip
}

# Función para configurar Apache
configurar_apache() {
    dialog --infobox "Configurando Apache..." 5 40
    sudo bash -c "cat <<EOL >/etc/apache2/sites-available/$DOMAIN.conf
<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    ServerName $DOMAIN
    DocumentRoot /var/www/matomo
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    <Directory /var/www/matomo/>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL"

    sudo a2ensite "$DOMAIN.conf"
    sudo a2enmod rewrite
    sudo systemctl reload apache2 || error_exit "Error al configurar Apache."
}

# Función para generar un certificado SSL
generar_certificado_ssl() {
    if ! command -v certbot &> /dev/null; then
        dialog --msgbox "Instalando Certbot para gestionar SSL..." 6 40
        sudo apt-get install -y certbot python3-certbot-apache || error_exit "Error al instalar Certbot."
    fi

    dialog --infobox "Generando certificado SSL para $DOMAIN..." 5 40
    sudo certbot --apache -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" || error_exit "Error al generar el certificado SSL."
}

# Función para crear la base de datos y usuario
crear_base_datos() {
    dialog --infobox "Creando base de datos y usuario..." 5 40
    sudo mysql -u root -e "CREATE DATABASE $DB_NAME;" || error_exit "Error al crear la base de datos."
    sudo mysql -u root -e "CREATE USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASSWORD';" || error_exit "Error al crear el usuario de la base de datos."
    sudo mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'$DB_HOST';" || error_exit "Error al conceder permisos."
    sudo mysql -u root -e "FLUSH PRIVILEGES;" || error_exit "Error al aplicar los cambios."
}

# Función para finalizar la instalación
finalizar_instalacion() {
    dialog --msgbox "Instalación de Matomo completada con SSL. Acceda a https://$DOMAIN para continuar con la configuración." 8 40
}

# Programa principal
verificar_dialog
verificar_db_instalada
instalar_dependencias
instalar_matomo
configurar_apache
generar_certificado_ssl
crear_base_datos
finalizar_instalacion

exit 0
