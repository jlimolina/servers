#!/bin/bash

# Función para verificar si MariaDB o MySQL están instalados
verificar_db() {
    if command -v mysql >/dev/null 2>&1; then
        DB_INSTALLED="mysql"
    elif command -v mariadb >/dev/null 2>&1; then
        DB_INSTALLED="mariadb"
    else
        DB_OPTION=$(dialog --menu "No se detectó ningún sistema de base de datos instalado. ¿Cuál deseas instalar?" 15 50 2 \
            1 "MySQL" \
            2 "MariaDB" 3>&1 1>&2 2>&3)

        case $DB_OPTION in
            1)
                DB_INSTALLED="mysql"
                dialog --infobox "Instalando MySQL..." 6 40
                sleep 2
                sudo apt update && sudo apt install -y mysql-server
                ;;
            2)
                DB_INSTALLED="mariadb"
                dialog --infobox "Instalando MariaDB..." 6 40
                sleep 2
                sudo apt update && sudo apt install -y mariadb-server
                ;;
            *)
                dialog --msgbox "No seleccionaste ningún sistema de base de datos. El proceso no puede continuar." 6 40
                exit 1
                ;;
        esac
    fi
}

# Función para instalar dependencias
instalar_dependencias() {
    dialog --infobox "Instalando dependencias necesarias..." 6 40
    sleep 2
    sudo apt update

    # Agregar repositorio de PHP 8.1 y actualizar
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt update

    # Instalar Apache, PHP 8.1 y módulos requeridos
    sudo apt install -y apache2 php8.1 php8.1-{mysql,xml,curl,zip,gd,mbstring,xmlrpc,intl,soap} libapache2-mod-php8.1

    # Configurar PHP 8.1
    sudo a2dismod php7.*
    sudo a2enmod php8.1
    sudo systemctl restart apache2
}

# Función para configurar la base de datos
configurar_base_datos() {
    DB_NAME=$(dialog --inputbox "Introduce el nombre de la base de datos:" 8 40 3>&1 1>&2 2>&3)
    DB_USER=$(dialog --inputbox "Introduce el nombre de usuario de la base de datos:" 8 40 3>&1 1>&2 2>&3)

    # Solicitar la contraseña del usuario
    while true; do
        DB_PASS=$(dialog --passwordbox "Introduce la contraseña del usuario:" 8 40 3>&1 1>&2 2>&3)
        DB_PASS_CONFIRM=$(dialog --passwordbox "Confirma la contraseña del usuario:" 8 40 3>&1 1>&2 2>&3)
        if [ "$DB_PASS" == "$DB_PASS_CONFIRM" ]; then
            break
        else
            dialog --msgbox "Las contraseñas no coinciden. Inténtalo de nuevo." 6 40
        fi
    done

    dialog --infobox "Configurando la base de datos..." 6 40
    sleep 2

    if [ "$DB_INSTALLED" == "mysql" ]; then
        sudo mysql -e "CREATE DATABASE $DB_NAME;"
        sudo mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
        sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
        sudo mysql -e "FLUSH PRIVILEGES;"
    elif [ "$DB_INSTALLED" == "mariadb" ]; then
        sudo mariadb -e "CREATE DATABASE $DB_NAME;"
        sudo mariadb -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
        sudo mariadb -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
        sudo mariadb -e "FLUSH PRIVILEGES;"
    fi
}

# Función para descargar e instalar Moodle
descargar_moodle() {
    dialog --infobox "Descargando Moodle..." 6 40
    sleep 2
    wget -q https://download.moodle.org/download.php/direct/stable404/moodle-latest-404.tgz

    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Error al descargar Moodle. Verifica tu conexión a Internet." 6 40
        exit 1
    fi

    dialog --infobox "Instalando Moodle..." 6 40
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

# Función para generar un certificado SSL con Certbot
crear_certificado_ssl() {
    EMAIL=$(dialog --inputbox "Introduce tu correo electrónico (para el certificado SSL):" 8 40 3>&1 1>&2 2>&3)

    dialog --infobox "Instalando Certbot y generando el certificado SSL..." 6 50
    sleep 2
    sudo apt install -y certbot python3-certbot-apache
    sudo certbot --apache -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

    if [[ $? -ne 0 ]]; then
        dialog --msgbox "Error al generar el certificado SSL." 6 40
        exit 1
    fi

    dialog --msgbox "Certificado SSL generado correctamente. Tu sitio es accesible en https://$DOMAIN" 8 50
}

# Función para finalizar la instalación
finalizar_instalacion() {
    dialog --msgbox "Instalación completa. Accede a tu sitio en: https://$DOMAIN" 8 60
    dialog --msgbox "Datos de configuración para Moodle:\nBase de datos: $DB_NAME\nUsuario: $DB_USER\nContraseña: $DB_PASS" 10 60
}

# Ejecución del script
verificar_db
instalar_dependencias
configurar_base_datos
descargar_moodle
configurar_apache
crear_certificado_ssl
finalizar_instalacion

