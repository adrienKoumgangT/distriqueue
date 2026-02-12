# Generate self-signed certificates for testing
mkdir -p deploy/ssl
cd deploy/ssl

# Generate CA key
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 365 -key ca.key -out ca.crt \
    -subj "/C=US/ST=State/L=City/O=DistriQueue/CN=DistriQueue CA"

# Generate server certificate
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
    -subj "/C=US/ST=State/L=City/O=DistriQueue/CN=distriqueue.local"
openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key \
    -set_serial 01 -out server.crt
