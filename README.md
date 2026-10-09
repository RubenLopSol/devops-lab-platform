# OpenPanel Rebuild

Este repositorio local es un rebuild de practica del proyecto DevOps OpenPanel.
No pretende ser el proyecto final, sino un laboratorio
para practicar con precision la arquitectura, el workflow GitOps y el papel de
cada herramienta.


## Estructura Local

```text
openpanel-rebuild/
├── openpanel-app/       # Repo de aplicacion
├── openpanel-platform/  # Repo de plataforma / GitOps
└── LopezSole_Ruben_ProyectoFinal_full.zip
```

Repos remotos:

```text
App:      https://github.com/RubenLopSol/devops-lab-app
Platform: https://github.com/RubenLopSol/devops-lab-platform
```

## Componentes

### App repo

Ruta local:

```text
openpanel-app/
```

Contiene una aplicacion Node.js sencilla:

```text
src/server.js
```

Expone:

```text
GET /        Respuesta JSON visible para validar despliegues
GET /health  Endpoint usado por livenessProbe y readinessProbe
```

El workflow principal:

```text
.github/workflows/build-publish.yml
```

Responsabilidades:

- Ejecutarse cuando hay push a `main`.
- Construir una imagen Docker.
- Publicarla en GHCR.
- Etiquetarla con un tag basado en el commit, por ejemplo `main-558a42f`.
- Notificar al repo de plataforma mediante `repository_dispatch`.

### Platform repo

Ruta local:

```text
openpanel-platform/
```

Contiene la declaracion GitOps del cluster:

```text
k8s/
├── apps/
│   ├── base/openpanel/
│   └── overlays/dev/openpanel/
└── infrastructure/
    └── base/argocd/
```

Responsabilidades:

- Definir manifests Kubernetes.
- Organizar base y overlays con Kustomize.
- Instalar ArgoCD usando Helm renderizado por Kustomize.
- Declarar ArgoCD Applications.
- Actualizar el estado deseado cuando se publica una nueva imagen de la app.

Workflow principal actual:

```text
.github/workflows/cd-update-image-tag.yml
```

Responsabilidades:

- Recibir el evento `app-image-published`.
- Actualizar el tag de imagen en el overlay de OpenPanel.
- Crear o usar una revision de release, por ejemplo `release/main-558a42f`.
- Actualizar la `Application` de ArgoCD para apuntar a esa revision.
- Hacer commit y push del nuevo estado deseado.

Este workflow no es un pipeline general de infraestructura. Solo actualiza la
version de la imagen de OpenPanel cuando la app publica una imagen nueva.

## Cluster

Cluster local:

```text
Minikube profile/context: openpanel-rebuild
```

Namespaces principales:

```text
argocd     ArgoCD y sus componentes
openpanel  Aplicacion OpenPanel
```

Comandos utiles:

```bash
kubectl config use-context openpanel-rebuild
kubectl get applications -n argocd
kubectl get pods -n argocd
kubectl get deployment openpanel-app -n openpanel
```

## ArgoCD

ArgoCD esta instalado dentro del cluster como workloads Kubernetes en el
namespace `argocd`.

Componentes importantes:

```text
argocd-server                  UI/API de ArgoCD
argocd-application-controller  Controller que reconcilia Applications
argocd-repo-server             Descarga/renderiza contenido desde Git
argocd-redis                   Cache interna
argocd-dex-server              Autenticacion
```

ArgoCD no es un demonio externo del master. Es una aplicacion que corre dentro
de Kubernetes y usa permisos para gestionar otros recursos.

## ArgoCD Applications

Una `Application` de ArgoCD no es la aplicacion final. Es una orden declarativa
que ArgoCD sabe leer.

Una Application indica:

- Repo Git.
- Ruta dentro del repo.
- Revision, branch o tag.
- Cluster destino.
- Namespace destino.
- Politica de sincronizacion.

Modelo actual:

```text
argocd-applications
  watches: k8s/infrastructure/base/argocd/applications
  applies: ArgoCD Application objects

openpanel-dev
  watches: k8s/apps/overlays/dev/openpanel
  applies: real OpenPanel Kubernetes resources
```

Esto sigue el patron app-of-apps:

```text
bootstrap-app.yaml
   ↓ crea la Application raiz
Application/argocd-applications
   ↓ gestiona otras Applications desde Git
Application/openpanel-dev
   ↓ despliega manifests reales
Deployment/Service/ConfigMap/Namespace
   ↓ crean la app en Kubernetes
Pods de OpenPanel
```

## Flujo GitOps Completo

Flujo validado durante el rebuild:

```text
1. Se cambia codigo en openpanel-app.
2. Se hace commit y push a main.
3. GitHub Actions del repo app construye la imagen.
4. La imagen se publica en GHCR con tag basado en commit.
5. El repo app envia repository_dispatch al repo plataforma.
6. GitHub Actions del repo plataforma actualiza el estado deseado.
7. El overlay dev usa el nuevo tag de imagen.
8. La Application openpanel-dev apunta al nuevo release tag.
9. ArgoCD detecta el cambio en Git.
10. ArgoCD sincroniza el cluster.
11. Kubernetes actualiza el Deployment con RollingUpdate.
12. La app responde con el nuevo comportamiento.
```

Ejemplo real validado:

```text
Commit app:       558a42f
Image tag:        main-558a42f
ArgoCD revision:  release/main-558a42f
Deployment image: ghcr.io/rubenlopsol/devops-lab-app:main-558a42f
```

## Deployment Strategy

El Deployment de OpenPanel usa:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%
    maxUnavailable: 25%
```

Tambien usa probes sobre `/health`:

```text
readinessProbe  Decide si el pod puede recibir trafico.
livenessProbe   Decide si el contenedor esta vivo o debe reiniciarse.
```

Con `replicas: 1`, Kubernetes intenta crear un pod nuevo, esperar a que este
Ready y despues retirar el pod anterior. Esto reduce downtime, aunque no da alta
disponibilidad real porque solo hay una replica.

## Comandos De Verificacion

Estado de ArgoCD:

```bash
kubectl get applications -n argocd
```

Revision usada por la Application:

```bash
kubectl get application openpanel-dev -n argocd -o jsonpath='{.spec.source.targetRevision}'; echo
```

Imagen desplegada:

```bash
kubectl get deployment openpanel-app -n openpanel -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

Probar la app:

```bash
kubectl port-forward svc/openpanel-app -n openpanel 3000:80
curl http://localhost:3000/
```

Acceso a ArgoCD UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8081:443
```

URL:

```text
https://localhost:8081
```

## Principios Del Rebuild

- Git es la fuente de verdad.
- El cluster es el resultado, no el lugar donde se hacen cambios persistentes.
- ArgoCD reconcilia estado deseado contra estado real.
- GitHub Actions prepara y actualiza el estado deseado.
- Kustomize organiza bases y overlays.
- Helm se usa renderizado por Kustomize para componentes de plataforma.
- No se usan instalaciones manuales con `helm install` para componentes de
  plataforma.
- No se introducen herramientas extra, como KEDA u observabilidad, hasta que el
  workflow principal este completamente interiorizado.

## Mejora Futura Anotada

Mas adelante se anadira un workflow separado de validacion para el repo
plataforma.

Ese workflow deberia ejecutarse en `push` y `pull_request` del repo plataforma,
renderizar rutas importantes con Kustomize/Helm y verificar manifests sin
desplegar directamente.

No debe mezclarse con el workflow actual de actualizacion de imagen, porque son
responsabilidades distintas.
