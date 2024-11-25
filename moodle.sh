#!/bin/bash

# Función para seleccionar el sistema de base de datos
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

# Función para instalar dependencias
instalar_dependencias() {
    dialog --infobox "Instalando dependencias..." 6 40
    sleep 2
    sudo apt update

    # Agregar el repositorio de PHP 8.1
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt update

    # Instalar PHP 8.1 y módulos necesarios
    sudo apt install -y apache2 php8.1 php8.1-{mysql,xml,curl,zip,gd,mbstring,xmlrpc,intl,soap} libapache2-mod-php8.1

    # Deshabilitar PHP 7.x si está activo y habilitar PHP 8.1 en Apache
    sudo a2dismod php7.*
    sudo a2enmod php8.1
    sudo systemctl restart apache2

    # Instalar MySQL o MariaDB según la selección
    if [ "$DB_TYPE" == "mysql" ]; then
        sudo apt install -y mysql-server
    else
        sudo apt install -y mariadb-server
    fi
}


# Función para configurar la base de datos
configurar_base_datos() {
    DB_NAME=$(dialog --inputbox "Introduce el nombre de la base de datos:" 8 40 3>&1 1>&2 2>&3)
    DB_USER=$(dialog --inputbox "Introduce el nombre de usuario de la base de datos:" 8 40 3>&1 1>&2 2>&3)
    DB_PASS=$(dialog --passwordbox "Introduce la contraseña del usuario:" 8 40 3>&1 1>&2 2>&3)

    dialog --infobox "Configurando la base de datos..." 6 40
    sleep 2

    sudo mysql -e "CREATE DATABASE $DB_NAME;"
    sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
}

# Función para descargar Moodle
descargar_moodle() {
    dialog --infobox "Descargando Moodle..." 6 40
    sleep 2
    wget -q https://download.moodle.org/download.php/direct/stable404/moodle-latest-404.tgz

    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Error al descargar Moodle. Verifica tu conexión a Internet." 6 40
        exit 1
    fi

    dialog --infobox "Descomprimiendo Moodle..." 6 40
    sleep 2
    tar -xzf moodle-latest-404.tgz
    sudo mv moodle /var/www/moodle
    sudo chown -R www-data:www-data /var/www/moodle
    sudo chmod -R 755 /var/www/moodle

    rm moodle-latest-404.tgz
}

# Función para configurar Apache
configurar_apache() {
    DOMAIN=$(dialog --inputbox "Introduce tu dominio (ejemplo.com):" 8 40 3>&1 1>&2 2>&3)

    sudo bash -c "cat > /etc/apache2/sites-available/moodle.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot /var/www/moodle

    <Directory /var/www/moodle>
        AllowOverride All
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF"

    sudo a2ensite moodle.conf
    sudo a2dissite 000-default.conf
    sudo systemctl restart apache2
}

# Función para generar un certificado SSL
crear_certificado_ssl() {
    dialog --infobox "Instalando Certbot y generando certificado SSL..." 6 50
    sleep 2
    sudo apt install -y certbot python3-certbot-apache

    # Generar certificado SSL con Certbot
    sudo certbot --apache -d $DOMAIN --non-interactive --agree-tos -m tu-email@example.com

    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Error al generar el certificado SSL." 6 40
        exit 1
    fi

    dialog --msgbox "Certificado SSL generado correctamente. Tu sitio ya es accesible a través de https://$DOMAIN" 8 50
}

# Modificar la función para finalizar la instalación
finalizar_instalacion() {
    dialog --msgbox "Instalación completa. Accede a tu sitio en: https://$DOMAIN" 8 60
    dialog --msgbox "Recuerda los siguientes datos para configurar Moodle:\nNombre de la base de datos: $DB_NAME\nUsuario de la base de datos: $DB_USER\nContraseña del usuario: $DB_PASS" 10 60
}

# Comenzar instalación de Moodle
seleccionar_db
instalar_dependencias
configurar_base_datos
descargar_moodle
configurar_apache
crear_certificado_ssl  # Añadir la generación del certificado SSL
finalizar_instalacion
