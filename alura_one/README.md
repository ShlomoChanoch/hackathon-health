# Instância Oracle Linux 9 para o MediFlow (Hackathon do Alura+ONE)

Variante do `hackathon-health` para o hackathon da ONE (Oracle Next Education).
Diferente do projeto da raiz, **esta pasta não cria rede**: ela sobe só a VM, dentro de uma
VCN, subnet e NSG que **já existem** no compartment da ONE.

No primeiro boot, a VM já liga o GitOps: clona o repositório da aplicação, faz login no OCIR e
ativa o timer do sync. O sync traz os containers (Caddy e MediFlow) de `deploy/` do repositório.
Nada de container é definido aqui.

## O que é criado

| Recurso | Detalhe |
|---|---|
| VM | Oracle Linux 9.8 (aarch64), `VM.Standard.A1.Flex` (Always Free), IP público, boot volume de 50 GB, tag `Mediflow.Instances = mediflow-vm` |
| Chave SSH | ed25519 gerada pelo Terraform em `~/.ssh/mediflow-<timestamp>` (sem passphrase) |
| DuckDNS | `mediflow-oci.duckdns.org` apontado para o IP da VM a cada IP novo (roda na sua máquina, com `curl`) |
| cloud-init | firewalld (22 e 443), Podman rootless, git, OCI CLI e o pontapé do GitOps |

> A imagem está fixada por OCID em `main.tf` (`Oracle-Linux-9.8-aarch64-2026.07.20-0`, região
> **us-ashburn-1**). O OCID de imagem muda por região: se trocar a região, pegue o OCID da mesma
> imagem na [página da Oracle](https://docs.oracle.com/iaas/images/oracle-linux-9x/oracle-linux-9-8-aarch64-2026-07-20-0.htm).

## Pré-requisitos

Nada disto é criado por esta pasta; precisa existir antes do `apply`.

- OCI CLI configurado (`oci setup config`), como no README da raiz, e `curl` na sua máquina.
- Terraform >= 1.5.
- **Rede**: compartment, VCN, subnet e NSG. O NSG libera entrada TCP 443 de `0.0.0.0/0`,
  TCP 22 só do `ssh_cidr`, e saída TCP 443 para `0.0.0.0/0`.
- **Tag**: namespace `Mediflow` com a key `Instances`.
- **Dynamic group** `Mediflow/mediflow-vm`:
  `ALL {instance.compartment.id = '<compartment>', tag.Mediflow.Instances.value = 'mediflow-vm'}`
- **Segredos no Vault**, criados no mesmo compartment da policy:
  - `mediflow-deploy-key`: chave **privada** de uma deploy key do repositório da aplicação
    (a pública vai em *GitHub → Settings → Deploy keys*, sem acesso de escrita);
  - o auth token do OCIR.
- **Policy** do dynamic group, lendo os dois segredos:
  ```
  Allow dynamic-group Mediflow/mediflow-vm to read secret-bundles in compartment <compartment> where any {target.secret.name = 'mediflow-deploy-key', target.secret.name = '<segredo-do-auth-token>'}
  ```
- **Repositório da aplicação** com `deploy/mediflow-sync.service` e `deploy/mediflow-sync.timer`.

Para gerar a deploy key (na sua máquina):

```bash
ssh-keygen -t ed25519 -f mediflow-deploy-key -N "" -C "mediflow-vm"
```

Depois de cadastrar a pública no GitHub e a privada no Vault, apague os dois arquivos.

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
| `shape`, `ocpus`, `memory` | `VM.Standard.A1.Flex`, `2`, `12` |
| `repo_ssh_url` | URL SSH do repositório da aplicação (`git@github.com:...`) |
| `ocir_user` | `<namespace>/<usuário>` do OCIR (`oci os ns get` mostra o namespace) |
| `deploy_key_secret_ocid`, `ocir_token_secret_ocid` | OCIDs dos dois segredos no Vault |
| `duckdns_domain`, `duckdns_token` | Subdomínio (`mediflow-oci`) e token da conta do DuckDNS |

O `terraform.tfvars` **não vai para o Git** (tem OCIDs, caminho de chave e o token do DuckDNS).
Os segredos do OCIR e do GitHub não passam pelo Terraform: só os OCIDs deles.

### 2. Suba a VM

```bash
terraform init
terraform plan
terraform apply
```

No fim do `apply`, o Terraform atualiza o DuckDNS com o IP novo. Se o DuckDNS não responder
`OK`, o `apply` falha nesse passo; dá para atualizar à mão em duckdns.org e seguir.

### 3. Espere o cloud-init

Do `apply` até o SSH responder leva alguns minutos (provisionamento + boot). Depois, o cloud-init
ainda roda uns **5 minutos** instalando pacotes, e o bootstrap pode esperar mais alguns minutos
até a VM ganhar acesso ao Vault. Dá para entrar por SSH enquanto ele roda.

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
STATUS vault: segredos acessíveis
STATUS git: clonado em /home/opc/mediflow
STATUS ocir: login ok
STATUS sync: timer ativo
STATUS sshd: active
STATUS firewalld: active
STATUS firewall (config): dhcpv6-client https ssh 22/tcp 443/tcp
```

e **nenhuma** linha `WARN`.

### 4. Confira o GitOps

Na VM (como `opc`, sem `sudo`):

```bash
systemctl --user list-timers mediflow-sync.timer
journalctl --user -u mediflow-sync.service -n 50
podman ps
```

Na sua máquina:

```bash
curl -sI https://mediflow-oci.duckdns.org | head -1
```

## O que o cloud-init faz

| Passo | Detalhe |
|---|---|
| DNS | Espera o DNS resolver antes de baixar qualquer coisa |
| Firewall | `firewall-offline-cmd`: serviço **e** porta para SSH (22) e HTTPS (443) |
| Pacotes | `git`, `podman`, `podman-docker` (alias `docker` → `podman`), `podman-compose` (do EPEL) e OCI CLI |
| Rootless | `loginctl enable-linger opc` (containers continuam após o logout) e portas a partir de 80 sem root |
| Smoke test | `podman run hello-world` → `/var/log/podman-hello.log` |
| GitOps | Script `/usr/local/sbin/mediflow-bootstrap.sh` (veja abaixo) |
| Diagnóstico | Linhas `STATUS` no fim do log |

O bootstrap do GitOps, com instance principal:

1. espera a VM conseguir ler o Vault (a entrada no dynamic group pode levar alguns minutos);
2. grava a deploy key em `~/.ssh/github_deploy` do `opc` e aponta o `github.com` para ela no `~/.ssh/config`;
3. clona o repositório em `/home/opc/mediflow`;
4. faz `podman login iad.ocir.io` como `opc`, gravando em `~/.config/containers/auth.json`
   (o padrão do rootless fica em `/run/user`, que é apagado a cada reboot);
5. copia `mediflow-sync.service` e `mediflow-sync.timer` de `deploy/` para `~/.config/systemd/user/`,
   ativa o timer e dispara a primeira execução do sync.

Todo comando que pode ficar esperando roda com `timeout`. Se algo estourar o tempo, aparece um
`WARN` no log e o resto continua: o cloud-init nunca fica travado. Nenhum segredo vai para o log.

## Comandos úteis

| Para | Comando |
|---|---|
| Entrar na VM | `$(terraform output -raw ssh_command)` |
| Ver o IP | `terraform output -raw public_ip` |
| Recriar só a VM (ex.: mudou o cloud-init) | `terraform apply -replace=oci_core_instance.vm` |
| Apagar a VM | `terraform destroy` |
| Log do cloud-init | `sudo tail -f /var/log/cloud-init-output.log` |
| Rodar o bootstrap de novo | `sudo /usr/local/sbin/mediflow-bootstrap.sh` |
| Regras do firewall | `sudo firewall-cmd --list-all` |

- Mudanças no `cloud-init.yaml` **só valem numa VM nova** (`ignore_changes` no `user_data`):
  use o `-replace`. O IP público muda (o Terraform atualiza o DuckDNS); a chave SSH continua a mesma.
- O `terraform destroy` **não apaga o NSG, a VCN, a subnet, os segredos nem o dynamic group**
  (não são gerenciados aqui). Ele apaga a chave `mediflow-*` do seu `~/.ssh`.

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

**`WARN: sem acesso ao Vault`**
A VM não conseguiu ler os segredos em ~5 minutos. Confira a tag da VM, a regra do dynamic group,
a policy (nomes dos segredos e compartment) e os OCIDs no `terraform.tfvars`. Corrigido isso,
rode o bootstrap de novo na VM; não precisa recriar.

**Aviso `connection is not using a post-quantum key exchange algorithm`**
Vem do seu cliente SSH (OpenSSH 10.1+). O OpenSSH do Oracle Linux 9 não tem esses algoritmos.
A conexão continua segura; pode ignorar.

**Mensagem `Activate the web console with: systemctl enable --now cockpit.socket`**
Propaganda do Cockpit no login. Não precisa ativar. Para sumir: `sudo rm -f /etc/motd.d/cockpit`.

**Não use `firewall-cmd` dentro do cloud-init**
Ele trava (fica esperando o D-Bus do firewalld). Por isso o cloud-init usa `firewall-offline-cmd`.
Depois de logado na VM, `firewall-cmd` funciona normalmente.

## Arquivos

| Arquivo | Conteúdo |
|---|---|
| `main.tf` | Provider, chave SSH, a VM (imagem fixada por OCID) e a atualização do DuckDNS |
| `variables.tf` | Variáveis |
| `outputs.tf` | `instance_id`, `public_ip`, `ssh_command`, `ssh_private_key_path`, `ssh_user`, `vcn_id`, `subnet_id` |
| `versions.tf` | Versões do Terraform e dos providers (`oci`, `tls`, `local`, `time`) |
| `cloud-init.yaml` | Configuração da VM no primeiro boot, incluindo o bootstrap do GitOps |
| `tfvars.exemplo` | Modelo do `terraform.tfvars` |