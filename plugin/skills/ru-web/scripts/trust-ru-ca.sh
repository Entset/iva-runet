#!/usr/bin/env bash
# Доверие к сертификатам Минцифры (Russian Trusted Root/Sub CA) — без него zakupki.gov.ru и часть госсайтов
# отдают TLS-ошибку. Решение владельца: это корневой сертификат, которому браузер начнёт доверять для ВСЕХ сайтов.
#   trust-ru-ca.sh          — Chrome/agent-browser этого пользователя (NSS ~/.pki/nssdb) + PEM-бандл для Node
#   откат: certutil -D -d sql:$HOME/.pki/nssdb -n "Russian Trusted Root CA"; то же для "Russian Trusted Sub CA"
set -euo pipefail
D=${RUWEB_HOME:-$HOME/.iva-browser}/certs
mkdir -p "$D"
for n in root sub; do
  curl -fsSL --max-time 30 -o "$D/russian_trusted_${n}_ca.crt" "https://gu-st.ru/content/lending/russian_trusted_${n}_ca_pem.crt"
  openssl x509 -in "$D/russian_trusted_${n}_ca.crt" -noout -subject -fingerprint -sha256
done
cat "$D"/russian_trusted_{root,sub}_ca.crt > "$D/russian_ca_bundle.pem"
command -v certutil >/dev/null || { echo "нет certutil: sudo apt install -y libnss3-tools — и запусти снова"; exit 1; }
mkdir -p "$HOME/.pki/nssdb"
[ -f "$HOME/.pki/nssdb/cert9.db" ] || certutil -N -d "sql:$HOME/.pki/nssdb" --empty-password
certutil -A -d "sql:$HOME/.pki/nssdb" -n "Russian Trusted Root CA" -t "C,," -i "$D/russian_trusted_root_ca.crt"
certutil -A -d "sql:$HOME/.pki/nssdb" -n "Russian Trusted Sub CA" -t ",," -i "$D/russian_trusted_sub_ca.crt"
echo "OK: браузер доверяет. Дальше по желанию владельца:"
echo "  Node внутри Ивы (web_fetch): добавить в ~/iva/.env строку  NODE_EXTRA_CA_CERTS=$D/russian_ca_bundle.pem  и iva restart"
echo "  Вся система (curl, python):  sudo cp $D/russian_trusted_*_ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
