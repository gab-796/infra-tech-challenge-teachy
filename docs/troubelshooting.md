# Erros e seus tratamentos

## Caso algum container apresente o erro too many open files

Para o Fedora:

``` 
sudo nano /etc/sysctl.d/99-inotify.conf
fs.inotify.max_user_watches=1048576
fs.inotify.max_user_instances=2048

sudo sysctl --system
```

Nota: Essas configs já nascem com o cluster kind, mas podem se perder por reinicio de VM ou host.
Já está com a persistencia la, mas vai que...