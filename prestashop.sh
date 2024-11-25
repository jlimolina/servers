#!/bin/bash

# Verificar si el paquete dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "El paquete 'dialog' no está instalado. Instalando..."
    sudo apt-get update && sudo apt-get install -y dialog
fi

# Función para mostrar mensajes de error y salir
error_exit() {
    dialog --msgbox "$1" 8 40
    exit 1
}

# Función para verificar si MySQL o MariaDB están instalados
verificar_instalacion_db() {
    if command -v mysql &> /dev/null; then
        dialog --msgbox "MySQL está instalado." 6 30
    elif command -v mariadb &> /dev/null; then
        dialog --msgbox "MariaDB está instalado." 6 30
    else
        # Preguntar al usuario qué base de datos desea instalar
        DB_CHOICE=$(dialog --menu "Ninguna base de datos (MySQL o MariaDB) está instalada. ¿Qué desea instalar?" 15 50 2 \
            "MariaDB" "Instalar MariaDB" \
            "MySQL" "Instalar MySQL" \
            3>&1 1>&2 2>&3)

        case $? in
            0)  # Usuario seleccionó OK
                case $DB_CHOICE in
                    "MariaDB")
                        dialog --msgbox "Instalando MariaDB..." 6 30
                        sudo apt-get update && sudo apt-get install -y mariadb-server || error_exit "Error al instalar MariaDB."
                        ;;
                    "MySQL")
                        dialog --msgbox "Instalando MySQL..." 6 30
                        sudo apt-get update && sudo apt-get install -y mysql-server || error_exit "Error al instalar MySQL."
                        ;;
                    *)  # Opción no válida
                        dialog --msgbox "Opción no válida." 6 30
                        exit 1
                        ;;
                esac
                ;;
            1)  # Usuario seleccionó Cancel
                exit 1
                ;;
            255)  # Usuario cerró la ventana de diálogo
                exit 1
                ;;
        esac
    fi
}

# Llamar a la función para verificar la instalación de la base de datos
verificar_instalacion_db

# Recopilar la información necesaria del usuario
DB_NAME=$(dialog --inputbox "Ingrese el nombre de la base de datos:" 8 40 3>&1 1>&2 2>&3)
DB_USER=$(dialog --inputbox "Ingrese el nombre de usuario de la base de datos:" 8 40 3>&1 1>&2 2>&3)
DB_PASSWORD=$(dialog --passwordbox "Ingrese la contraseña del usuario de la base de datos:" 8 40 3>&1 1>&2 2>&3)
DB_HOST=$(dialog --inputbox "Ingrese el nombre del host de la base de datos (por defecto: localhost):" 8 40 "localhost" 3>&1 1>&2 2>&3)

# Verificar si los campos no están vacíos
if [ -z "$DB_NAME" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASSWORD" ] || [ -z "$DB_HOST" ]; then
    error_exit "Todos los campos son obligatorios. La instalación se cancelará."
fi

# Solicitar el dominio al usuario
DOMAIN=$(dialog --inputbox "Ingrese el dominio para su sitio (ej. ejemplo.com):" 8 40 3>&1 1>&2 2>&3)

if [ -z "$DOMAIN" ]; then
    error_exit "El dominio es obligatorio. La instalación se cancelará."
fi

# Actualizar repositorios e instalar dependencias necesarias
dialog --infobox "Instalando dependencias necesarias..." 5 40
sudo apt-get update && sudo apt-get install -y apache2 php php-mysql libapache2-mod-php php-intl php-gd php-xml php-zip php-mbstring unzip || error_exit "Error al instalar las dependencias."

# Descargar PrestaShop desde el enlace proporcionado (versión 8.2.0)
dialog --infobox "Descargando PrestaShop..." 5 40
wget -O prestashop.zip https://github.com/PrestaShop/PrestaShop/releases/download/8.2.0/prestashop_8.2.0.zip || error_exit "Error al descargar PrestaShop."

# Descomprimir PrestaShop
dialog --infobox "Descomprimiendo PrestaShop..." 5 40
unzip prestashop.zip -d /var/www/prestashop || error_exit "Error al descomprimir PrestaShop."
rm prestashop.zip  # Eliminar el archivo ZIP después de descomprimir

# Establecer permisos
dialog --infobox "Estableciendo permisos..." 5 40
sudo chown -R www-data:www-data /var/www/prestashop
sudo chmod -R 755 /var/www/prestashop

# Crear archivo de configuración de Apache
dialog --infobox "Configurando Apache..." 5 40
sudo bash -c "cat <<EOL >/etc/apache2/sites-available/$DOMAIN.conf
<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    ServerName $DOMAIN
    DocumentRoot /var/www/prestashop
    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    <Directory /var/www/prestashop/>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL"

# Habilitar el nuevo sitio y módulo rewrite
sudo a2ensite "$DOMAIN.conf"
sudo a2enmod rewrite
sudo systemctl reload apache2 || error_exit "Error al configurar Apache."

# Instalar Certbot si no está instalado
if ! command -v certbot &> /dev/null; then
    dialog --msgbox "Instalando Certbot para gestionar SSL..." 6 40
    sudo apt-get install -y certbot python3-certbot-apache || error_exit "Error al instalar Certbot."
fi

# Generar certificado SSL usando Certbot
dialog --infobox "Generando certificado SSL para $DOMAIN..." 5 40
sudo certbot --apache -d "$DOMAIN" --non-interactive --agree-tos -m webmaster@"$DOMAIN" || error_exit "Error al generar el certificado SSL."

# Crear la base de datos y usuario
dialog --infobox "Creando base de datos y usuario..." 5 40
sudo mysql -u root -e "CREATE DATABASE $DB_NAME;" || error_exit "Error al crear la base de datos."
sudo mysql -u root -e "CREATE USER '$DB_USER'@'$DB_HOST' IDENTIFIED BY '$DB_PASSWORD';" || error_exit "Error al crear el usuario de la base de datos."
sudo mysql -u root -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'$DB_HOST';" || error_exit "Error al conceder permisos."
sudo mysql -u root -e "FLUSH PRIVILEGES;" || error_exit "Error al aplicar los cambios."
# Deshabilitar el sitio predeterminado de Apache
sudo a2dissite 000-default.conf
sudo systemctl reload apache2 || error_exit "Error al recargar Apache"

# Mensaje final
dialog --msgbox "Instalación de PrestaShop completada con SSL. Acceda a https://$DOMAIN para continuar con la configuración." 8 40

exit 0
