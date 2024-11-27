#!/bin/bash

# Comprobar si el usuario es root
if [ "$(id -u)" != "0" ]; then
    echo "Este script debe ejecutarse como root." >&2
    exit 1
fi

# Variables
DB_USER=""
DB_NAME=""
DB_PASS=""
DOMAIN=""
ADMIN_EMAIL=""
MAUTIC_DIR="/var/www/mautic"

# Función para obtener datos del usuario con dialog
get_parameters() {
    DB_USER=$(dialog --inputbox "Introduce el nombre del usuario para la base de datos:" 10 50 3>&1 1>&2 2>&3 3>&-)
    [ $? != 0 ] && echo "Cancelado." && exit 1

    DB_NAME=$(dialog --inputbox "Introduce el nombre de la base de datos:" 10 50 3>&1 1>&2 2>&3 3>&-)
    [ $? != 0 ] && echo "Cancelado." && exit 1

    DB_PASS=$(dialog --passwordbox "Introduce la contraseña para la base de datos:" 10 50 3>&1 1>&2 2>&3 3>&-)
    [ $? != 0 ] && echo "Cancelado." && exit 1

    DOMAIN=$(dialog --inputbox "Introduce el dominio donde estará Mautic (ej. mautic.midominio.com):" 10 50 3>&1 1>&2 2>&3 3>&-)
    [ $? != 0 ] && echo "Cancelado." && exit 1

    ADMIN_EMAIL=$(dialog --inputbox "Introduce el correo electrónico para los certificados SSL:" 10 50 3>&1 1>&2 2>&3 3>&-)
    [ $? != 0 ] && echo "Cancelado." && exit 1
}

# Instalar dependencias
install_dependencies() {
    echo "Instalando dependencias necesarias..."
    apt update && apt upgrade -y
    apt install -y apache2 mysql-server php libapache2-mod-php unzip dialog \
        php-curl php-mbstring php-zip php-intl php-xml php-imap php-gd certbot python3-certbot-apache
}

# Configurar MySQL
configure_mysql() {
    echo "Configurando base de datos MySQL..."
    mysql -e "CREATE DATABASE $DB_NAME;"
    mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
}

# Descargar e instalar Mautic
install_mautic() {
    echo "Descargando e instalando Mautic..."
    wget https://www.mautic.org/download/latest -O mautic.zip
    unzip mautic.zip -d $MAUTIC_DIR
    chown -R www-data:www-data $MAUTIC_DIR
    chmod -R 755 $MAUTIC_DIR
    rm mautic.zip
}

# Configurar Apache
configure_apache() {
    echo "Configurando Apache..."
    cat <<EOF >/etc/apache2/sites-available/mautic.conf
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $MAUTIC_DIR

    <Directory $MAUTIC_DIR>
        AllowOverride All
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/mautic_error.log
    CustomLog \${APACHE_LOG_DIR}/mautic_access.log combined
</VirtualHost>
EOF

    a2ensite mautic.conf
    a2enmod rewrite
    systemctl restart apache2
}

# Configurar SSL con Let's Encrypt
configure_ssl() {
    echo "Instalando certificado SSL con Let's Encrypt..."
    certbot --apache -d $DOMAIN --non-interactive --agree-tos -m $ADMIN_EMAIL
}

# Configurar tareas programadas
configure_cron() {
    echo "Configurando tareas programadas..."
    crontab -l > mautic_cron
    echo "*/5 * * * * php $MAUTIC_DIR/bin/console mautic:segments:update" >> mautic_cron
    echo "*/5 * * * * php $MAUTIC_DIR/bin/console mautic:campaigns:trigger" >> mautic_cron
    echo "0 0 * * * php $MAUTIC_DIR/bin/console mautic:emails:send" >> mautic_cron
    crontab mautic_cron
    rm mautic_cron
}

# Ejecutar el instalador de Mautic
run_mautic_installer() {
    echo "Todo listo. Ahora accede a http://$DOMAIN y sigue el asistente de configuración de Mautic."
}

# Ejecución principal
main() {
    get_parameters
    install_dependencies
    configure_mysql
    install_mautic
    configure_apache
    configure_ssl
    configure_cron
    run_mautic_installer
}

main
