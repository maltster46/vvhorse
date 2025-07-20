# vvhorse
Config for Trojan protocol server

### Prerequisites

* A server running Ubuntu
* A domain name (A-record DNS entry) pointing to your server's IP address (required for TLS)
  * used as **domain** variable in script below

### How to use

Run on your server
```
sudo bash -c "$(wget -O- https://raw.githubusercontent.com/maltster46/vvhorse/refs/heads/main/setup.sh)"
```