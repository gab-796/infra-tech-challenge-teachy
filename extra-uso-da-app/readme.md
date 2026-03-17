# Usando a collection

Basta importar para o Postman ou Insomnia e será possível usar os 4 métodos que essa API suporta.
Ela funciona com o ingress, então é necessário ter atualizado o /etc/hosts com os dados corretos.


## /etc/hosts

Adicione essa linha no seu arquivo /etc/hosts:


`172.18.0.0 grafana-mimir.local loki.local inventory.local grafana-web.local mailhog.local minio.local alertmanager.local`


> Atenção: Verifique se a sua rede docker usada pelo kind faz parte do CIDR padrão(172.18.0.0/32)