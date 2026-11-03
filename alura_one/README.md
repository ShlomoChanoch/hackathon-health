# Instância Oracle Linux 8 para o Medfilow (Hackathon do Alura+ONE)

Variante do `hackathon-health` para o hackathon da ONE (Oracle Next Education).
Diferente do projeto da raiz, **esta pasta não cria rede**: ela sobe só a VM, dentro de uma
VCN, subnet e NSG que **já existem** no compartment da ONE.
 
## O que é criado
 
| Recurso | Detalhe |
|---|---|
| VM | Oracle Linux 8.10 (aarch64), `VM.Standard.A1.Flex` (Always Free), IP público, boot volume de 50 GB |
| Chave SSH | ed25519 gerada pelo Terraform em `~/.ssh/mediflow-<timestamp>` (sem passphrase) |
| cloud-init | firewalld, Podman rootless, alias `docker`, podman-compose e smoke test |
 
O que **não** é criado (precisa existir antes): compartment, VCN, subnet e NSG.
 
> A imagem está fixada por OCID em `main.tf` (`Oracle-Linux-8.10-aarch64-2026.06.15-0`, região
> **us-ashburn-1**). O OCID de imagem muda por região: se trocar a região, pegue o OCID da mesma
> imagem na [página da Oracle](https://docs.oracle.com/en-us/iaas/images/oracle-linux-8x/oracle-linux-8-10-aarch64-2026-06-15-0.htm).
 
## Pré-requisitos
 
- OCI CLI configurado (`oci setup config`), como no README da raiz.
- Terraform >= 1.5.
- OCIDs do compartment, da VCN, da subnet e do NSG da ONE.
- O NSG precisa liberar: TCP 22 (só do seu IP), TCP 80, 443 e a `demo_port` (8080).
## Passo a passo
 
### 1. Preencha o `terraform.tfvars`
 
```bash
cd alura_one
cp tfvars.exemplo terraform.tfvars
```
 
| Campo | O que colocar |
|---|---|
| `tenancy_ocid`, `user_ocid`, `fingerprint`, `private_key_path` | Os mesmos do `oci setup config` |
| `region` | `us-ashburn-1` (região da imagem fixada) |
| `compartment_ocid` | Compartment da ONE |
| `vcn_id`, `subnet_id`, `nsg_id` | OCIDs da rede já existente |
| `subnet_cidr` | CIDR da subnet (só informativo) |
| `ssh_cidr` | Seu IP: `curl -s4 ifconfig.me \| sed 's/$/\/32/'` |
| `demo_port` | Porta da aplicação (padrão `8080`) |
| `shape`, `ocpus`, `memory` | `VM.Standard.A1.Flex`, `2`, `12` |
 
O `terraform.tfvars` **não vai para o Git** (tem OCIDs e caminho de chave).
 
### 2. Suba a VM
 
```bash
terraform init
terraform plan
terraform apply
```
 
### 3. Espere o cloud-init
 
Do `apply` até o SSH responder leva alguns minutos (provisionamento + boot). Depois, o cloud-init
ainda roda uns **5 minutos** instalando pacotes. Dá para entrar por SSH enquanto ele roda.
 
```bash
$(terraform output -raw ssh_command)
```
 
Na VM:
 
```bash
cloud-init status --wait
grep -E "STATUS|WARN" /var/log/cloud-init-output.log
```
 
O esperado é:
 
```
STATUS sshd: active
STATUS firewalld: active
STATUS firewall (config): dhcpv6-client http https ssh 22/tcp 80/tcp 443/tcp 8080/tcp
```
 
e **nenhuma** linha `WARN`.
 
### 4. Teste de ponta a ponta
 
Na VM (como `opc`, sem `sudo`):
 
```bash
podman run -d --rm --name teste -p 8080:80 docker.io/library/nginx:alpine
```
 
Na sua máquina, dentro de `alura_one`:
 
```bash
curl -sI http://$(terraform output -raw public_ip):8080 | head -1   # HTTP/1.1 200 OK
```
 
Depois: `podman stop teste`.
 
## O que o cloud-init faz
 
| Passo | Detalhe |
|---|---|
| DNS | Espera o DNS resolver antes de baixar qualquer coisa |
| Firewall | `firewall-offline-cmd`: serviço **e** porta para SSH (22), HTTP (80), HTTPS (443) e a `demo_port` |
| Pacotes | `git`, `podman`, `podman-docker` (alias `docker` → `podman`) e `podman-compose` (do EPEL) |
| Rootless | `loginctl enable-linger opc` (containers continuam após o logout) e portas a partir de 80 sem root |
| Smoke test | `podman run hello-world` → `/var/log/podman-hello.log` |
| Diagnóstico | Linhas `STATUS` no fim do log |
 
Todo comando que pode ficar esperando roda com `timeout`. Se algo estourar o tempo, aparece um
`WARN` no log e o resto continua: o cloud-init nunca fica travado.
 
## Comandos úteis
 
| Para | Comando |
|---|---|
| Entrar na VM | `$(terraform output -raw ssh_command)` |
| Ver o IP | `terraform output -raw public_ip` |
| Recriar só a VM (ex.: mudou o cloud-init) | `terraform apply -replace=oci_core_instance.vm` |
| Apagar a VM | `terraform destroy` |
| Log do cloud-init | `sudo tail -f /var/log/cloud-init-output.log` |
| Regras do firewall | `sudo firewall-cmd --list-all` |
 
- Mudanças no `cloud-init.yaml` **só valem numa VM nova** (`ignore_changes` no `user_data`):
  use o `-replace`. O IP público muda; a chave SSH continua a mesma.
- O `terraform destroy` **não apaga o NSG, a VCN nem a subnet** (não são gerenciados aqui).
  Ele apaga a chave `mediflow-*` do seu `~/.ssh`.
## Problemas conhecidos
 
**`Connection refused` logo depois do `apply`**
A VM ainda está bootando. Espere alguns minutos. Para ver o boot sem SSH:
 
```bash
INST=$(terraform output -raw instance_id)
ID=$(oci compute console-history capture --instance-id "$INST" \
  --wait-for-state SUCCEEDED --query 'data.id' --raw-output 2>/dev/null)
oci compute console-history get-content --instance-console-history-id "$ID" \
  --length 10000000 --file - 2>/dev/null | tail -30
```
 
Cada captura é uma foto daquele momento: para ver o progresso, capture de novo.
 
**Aviso `connection is not using a post-quantum key exchange algorithm`**
Vem do seu cliente SSH (OpenSSH 10.1+). O OpenSSH do Oracle Linux 8 não tem esses algoritmos.
A conexão continua segura; pode ignorar.
 
**Mensagem `Activate the web console with: systemctl enable --now cockpit.socket`**
Propaganda do Cockpit no login. Não precisa ativar. Para sumir: `sudo rm -f /etc/motd.d/cockpit`.
 
**`podman-compose` é a versão 1.0.6**
Cobre o básico (`services`, `ports`, `volumes`, `environment`, `depends_on` simples). Recursos
novos, como `depends_on` com `condition: service_healthy`, podem não funcionar como no Docker Compose.
 
**Não use `firewall-cmd` dentro do cloud-init**
Ele trava (fica esperando o D-Bus do firewalld). Por isso o cloud-init usa `firewall-offline-cmd`.
Depois de logado na VM, `firewall-cmd` funciona normalmente.
 
## Arquivos
 
| Arquivo | Conteúdo |
|---|---|
| `main.tf` | Provider, chave SSH e a VM (imagem fixada por OCID) |
| `variables.tf` | Variáveis |
| `outputs.tf` | `instance_id`, `public_ip`, `ssh_command`, `ssh_private_key_path`, `ssh_user`, `vcn_id`, `subnet_id`, `nsg_id` |
| `versions.tf` | Versões do Terraform e dos providers (`oci`, `tls`, `local`, `time`) |
| `cloud-init.yaml` | Configuração da VM no primeiro boot |
| `tfvars.exemplo` | Modelo do `terraform.tfvars` |
