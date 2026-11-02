#!/usr/bin/env bash
# Доверие к сертификатам Минцифры (Russian Trusted Root/Sub CA, Sub CA два: старый и 2024) — без них zakupki.gov.ru,
# torgi.gov.ru и часть госсайтов
# отдают TLS-ошибку. Решение владельца: это корневой сертификат, которому браузер начнёт доверять для ВСЕХ сайтов.
#   trust-ru-ca.sh          — Chrome/agent-browser этого пользователя (NSS ~/.pki/nssdb) + PEM-бандл для Node
#   откат: certutil -D -d sql:$HOME/.pki/nssdb -n "Russian Trusted Root CA"; для "Russian Trusted Sub CA" — дважды
set -euo pipefail
D=${RUWEB_HOME:-$HOME/.iva-browser}/certs
mkdir -p "$D"
for n in root_ca sub_ca sub_ca_2024; do
  # openssl переписывает в чистый PEM: в файле с gu-st нет перевода строки в конце, и склейка выходит битой (curl: 77)
  curl -fsSL --max-time 30 "https://gu-st.ru/content/lending/russian_trusted_${n}_pem.crt" | openssl x509 -out "$D/russian_trusted_$n.crt"
  openssl x509 -in "$D/russian_trusted_$n.crt" -noout -subject -enddate -fingerprint -sha256
done
cat "$D"/russian_trusted_{root_ca,sub_ca,sub_ca_2024}.crt > "$D/russian_ca_bundle.pem"
command -v certutil >/dev/null || { echo "нет certutil: sudo apt install -y libnss3-tools — и запусти снова"; exit 1; }
mkdir -p "$HOME/.pki/nssdb"
[ -f "$HOME/.pki/nssdb/cert9.db" ] || certutil -N -d "sql:$HOME/.pki/nssdb" --empty-password
certutil -A -d "sql:$HOME/.pki/nssdb" -n "Russian Trusted Root CA" -t "C,," -i "$D/russian_trusted_root_ca.crt"
for n in sub_ca sub_ca_2024; do  # одно имя на оба: у них одинаковый subject, NSS хранит их под общим именем
  certutil -A -d "sql:$HOME/.pki/nssdb" -n "Russian Trusted Sub CA" -t ",," -i "$D/russian_trusted_$n.crt"
done
echo "OK: браузер доверяет. Дальше по желанию владельца:"
echo "  Node внутри Ивы (web_fetch): добавить в ~/iva/.env строку  NODE_EXTRA_CA_CERTS=$D/russian_ca_bundle.pem  и iva restart"
echo "  Вся система (curl, python):  sudo cp $D/russian_trusted_*.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
echo "  Не дописывать сертификаты в /etc/ssl/certs/ca-certificates.crt руками: так легко сломать TLS всей машине."
