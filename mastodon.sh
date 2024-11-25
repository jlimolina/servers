#!/bin/bash

# Verificar si el script se ejecuta como root
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecuta este script como root."
  exit 1
fi

# Instalar dialog si no está presente
if ! command -v dialog &> /dev/null; then
  apt update && apt install -y dialog
fi

# Variables de configuración
BACKTITLE="Instalador de Mastodon"
LOGFILE="/var/log/mastodon_install.log"

# Función para mostrar un mensaje de error
function error_message() {
  dialog --backtitle "$BACKTITLE" --msgbox "Error: $1" 10 40
  echo "Error: $1" >> "$LOGFILE"
  exit 1
}

# Función para ejecutar comandos con retroalimentación
function run_command() {
  echo "$1" >> "$LOGFILE"
  eval "$1" || error_message "No se pudo ejecutar: $1"
}

# Paso 1: Información inicial
dialog --backtitle "$BACKTITLE" --msgbox "Bienvenido al instalador de Mastodon.\n\nEste script instalará y configurará Mastodon en su servidor." 10 50

# Paso 2: Configuración de nombre de dominio
dialog --backtitle "$BACKTITLE" --inputbox "Introduce el dominio para Mastodon (ejemplo: mastodon.example.com):" 10 50 2> /tmp/mastodon_domain
DOMAIN=$(< /tmp/mastodon_domain)

if [ -z "$DOMAIN" ]; then
  error_message "El dominio es obligatorio."
fi

# Paso 3: Actualización del sistema
dialog --backtitle "$BACKTITLE" --infobox "Actualizando paquetes del sistema..." 10 40
run_command "apt update && apt upgrade -y"

# Paso 4: Instalación de dependencias
dialog --backtitle "$BACKTITLE" --infobox "Instalando dependencias necesarias..." 10 40
run_command "apt install -y git curl wget nginx postgresql redis ffmpeg imagemagick libpq-dev libxml2-dev libxslt1-dev file g++ gcc autoconf bison build-essential libssl-dev libyaml-dev libreadline-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev certbot python3-certbot-nginx"

# Paso 5: Instalación de Ruby y Node.js
dialog --backtitle "$BACKTITLE" --infobox "Instalando Ruby y Node.js..." 10 40
run_command "apt install -y rbenv"
run_command "rbenv install 3.2.2 && rbenv global 3.2.2"
run_command "curl -fsSL https://deb.nodesource.com/setup_18.x | bash -"
run_command "apt install -y nodejs && npm install -g yarn"

# Paso 6: Crear base de datos PostgreSQL
dialog --backtitle "$BACKTITLE" --infobox "Configurando PostgreSQL..." 10 40
run_command "sudo -u postgres createuser -d mastodon"
run_command "sudo -u postgres createdb -O mastodon mastodon_production"

# Paso 7: Configuración de Mastodon
dialog --backtitle "$BACKTITLE" --infobox "Clonando Mastodon..." 10 40
run_command "git clone https://github.com/mastodon/mastodon.git /home/mastodon"
run_command "cd /home/mastodon && git checkout $(git tag | grep -v 'rc' | tail -1)"
run_command "cd /home/mastodon && bundle install --deployment --without development test"
run_command "cd /home/mastodon && yarn install"

# Paso 8: Configuración del dominio
dialog --backtitle "$BACKTITLE" --infobox "Generando configuración para $DOMAIN..." 10 40
cd /home/mastodon || error_message "No se encontró el directorio de Mastodon."
run_command "cp .env.production.sample .env.production"
sed -i "s/localhost/$DOMAIN/g" .env.production

# Paso 9: Configuración de Nginx
dialog --backtitle "$BACKTITLE" --infobox "Configurando Nginx para $DOMAIN..." 10 40
cat <<EOF > /etc/nginx/sites-available/mastodon
server {
  listen 80;
  server_name $DOMAIN;

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF

ln -s /etc/nginx/sites-available/mastodon /etc/nginx/sites-enabled/
run_command "systemctl restart nginx"

# Paso 10: Configuración del Certificado SSL
dialog --backtitle "$BACKTITLE" --infobox "Instalando certificado SSL para $DOMAIN..." 10 40
run_command "certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN"

# Verificación del certificado
if [ $? -ne 0 ]; then
  error_message "La configuración del certificado SSL falló. Verifica que el dominio apunta correctamente al servidor."
fi

# Paso 11: Finalización
dialog --backtitle "$BACKTITLE" --msgbox "La instalación de Mastodon se ha completado. Ahora está configurado con HTTPS en $DOMAIN.\nPor favor, completa la configuración ejecutando los comandos en /home/mastodon." 10 50

# Limpiar archivos temporales
rm -f /tmp/mastodon_domain

exit 0
