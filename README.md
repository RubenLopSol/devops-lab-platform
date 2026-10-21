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
│   └── overlays/
│       ├── dev/openpanel/
│       └── prod/openpanel/
└── infrastructure/
    ├── base/
    │   ├── argocd/
    │   │   ├── applications/
    │   │   ├── install/
    │   │   └── projects/
    │   ├── local-path-provisioner/
    │   ├── namespaces/
    │   ├── argo-rollouts/
    │   ├── sealed-secrets/
    │   └── observability/
    │       ├── alertmanager/
    │       └── kube-prometheus-stack/
    └── overlays/dev/
        ├── argocd/
        └── observability/

Makefile
scripts/
├── setup-minikube.sh
└── install-argocd.sh
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
argocd                ArgoCD y sus componentes
openpanel             Aplicacion OpenPanel
observability         Prometheus y Alertmanager
sealed-secrets        Controlador Sealed Secrets
argo-rollouts         Controlador Argo Rollouts
local-path-storage    Controlador de almacenamiento local
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
bootstrap-app
  watches: k8s/infrastructure/overlays/dev/argocd
  applies: ArgoCD config, AppProjects, and Application objects

local-path-provisioner
  watches: k8s/infrastructure/base/local-path-provisioner
  applies: controller, RBAC, ConfigMap, and StorageClass/local-path

namespaces
  watches: k8s/infrastructure/base/namespaces
  applies: namespaces owned by platform components and the app

argo-rollouts
  watches: k8s/infrastructure/base/argo-rollouts
  applies: Rollouts controller, CRDs, and dashboard

sealed-secrets
  watches: k8s/infrastructure/base/sealed-secrets
  applies: Sealed Secrets controller

prometheus
  watches: k8s/infrastructure/overlays/dev/observability/kube-prometheus-stack
  applies: Prometheus Operator, Prometheus, node exporter y kube-state-metrics

alertmanager
  watches: k8s/infrastructure/overlays/dev/observability/alertmanager
  applies: Alertmanager y su ServiceMonitor

openpanel-dev
  watches: k8s/apps/overlays/dev/openpanel
  applies: real OpenPanel Kubernetes resources
```

Esto sigue el patron app-of-apps:

```text
bootstrap-app.yaml
   ↓ crea la Application raiz
Application/bootstrap-app
   ↓ gestiona el overlay dev de ArgoCD desde Git
AppProject/openpanel + Applications independientes
   ├── Application/openpanel-dev
   │     ↓ despliega Deployment/Service/ConfigMap en openpanel
   │     └── Pods de OpenPanel
   ├── Application/prometheus
   │     ↓ instala kube-prometheus-stack en observability
   ├── Application/alertmanager
   │     ↓ instala Alertmanager y su ServiceMonitor
   └── Application/local-path-provisioner (project: default)
         ↓ despliega RBAC/controller en local-path-storage
         └── StorageClass/local-path (cluster-scoped)
```

La Application `namespaces` gestiona `openpanel`, `argo-rollouts`,
`sealed-secrets` y `observability`. Las Applications `argo-rollouts` y
`sealed-secrets` instalan sus controladores en esos namespaces.

El controller corre en `local-path-storage`; la StorageClass es un recurso de
cluster. El provisioner crea volúmenes cuando un PVC los solicita. Prometheus
tiene un PVC de 5 Gi y Alertmanager uno de 1 Gi, ambos `Bound` mediante
`local-path`. OpenPanel todavía no solicita almacenamiento.

La Application del provisioner usa `project: default`, como en el original,
porque gestiona recursos de ámbito de clúster. El AppProject `openpanel` actual
restringe los recursos cluster-scoped permitidos.

El overlay `prod` reutiliza la misma base de OpenPanel y cambia la configuración
de entorno, etiquetas y anotaciones. El overlay de infraestructura `prod` crea
la Application `openpanel-prod` y su `bootstrap-app`; ambos renderizan
localmente, pero no se han aplicado ni desplegado. CI incluye el render de estos
overlays. `staging` se omite en este rebuild.

`scripts/install-argocd.sh [dev|prod]` y `make install-argocd ENVIRONMENT=dev|prod`
permiten elegir el overlay; por defecto usan `dev`. El script bloquea `prod` si
el contexto actual es `openpanel-rebuild`. Antes de desplegar producción se
necesita un destino separado y fijar las Applications a una release inmutable
del repositorio; no usar el clúster dev, donde se comparten nombres y namespace.

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

## Recrear El Cluster Desde Cero

En un cluster nuevo hay una excepcion normal al flujo GitOps: ArgoCD todavia no
existe, asi que no puede instalarse a si mismo. Hace falta un bootstrap manual
minimo. En este rebuild, igual que en el proyecto original, ese bootstrap queda
encapsulado en `Makefile` y scripts.

Orden recomendado desde cero:

```bash
make cluster-up
```

Ese target ejecuta:

```text
make cluster-start
make cluster-bootstrap
```

`cluster-start` arranca/selecciona Minikube. `cluster-bootstrap` instala o
reaplica ArgoCD y `bootstrap-app`. `cluster-up` ejecuta ambas fases.

`make cluster-delete` elimina el perfil Minikube y todo su estado local. Se
validó una recreación limpia ejecutando `make cluster-delete` y después
`make cluster-up`: las cuatro Applications volvieron a `Synced`/`Healthy`, y
OpenPanel y el provisioner volvieron a `Running`. No eliminar el perfil si se
necesitan sus datos locales.

Internamente, el script de ArgoCD usa dos pasadas, como el proyecto original.

Primera pasada: instala ArgoCD desde la base Helm/Kustomize para que existan el
controller y los CRDs:

```bash
kustomize build --enable-helm k8s/infrastructure/base/argocd/install | kubectl apply -f -
```

Este paso instala ArgoCD y deja configurado `argocd-cm` con:

```text
kustomize.buildOptions: --enable-helm --load-restrictor=LoadRestrictionsNone
```

Esa opcion es necesaria para que ArgoCD pueda renderizar el overlay de entorno,
porque `k8s/infrastructure/overlays/dev/argocd` usa `helmCharts` dentro de
Kustomize.

Segunda pasada: cuando ArgoCD y sus CRDs estan listos, aplica el overlay de
entorno completo:

```bash
kustomize build --enable-helm --load-restrictor=LoadRestrictionsNone k8s/infrastructure/overlays/dev/argocd | kubectl apply -f -
```

Finalmente aplica la Application raiz:

```bash
kubectl apply -f k8s/infrastructure/overlays/dev/argocd/bootstrap-app.yaml
```

A partir de ahi ArgoCD toma el control:

```text
Application/bootstrap-app
  -> k8s/infrastructure/overlays/dev/argocd
  -> AppProject/openpanel + Application/openpanel-dev
  -> k8s/apps/overlays/dev/openpanel
  -> recursos reales de OpenPanel

Application/local-path-provisioner
  -> k8s/infrastructure/base/local-path-provisioner
  -> controller y StorageClass/local-path
```

La frontera es:

```text
Antes de ArgoCD: bootstrap manual minimo.
Despues de ArgoCD: GitOps.
```

Comandos relacionados:

```bash
make help
make cluster-up
make cluster-start
make cluster-bootstrap
make cluster-stop
make cluster-delete
make status
make port-forward-argocd
make argocd-password
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
kubectl get pods -n local-path-storage
kubectl get storageclass local-path
kubectl get pods -n observability
kubectl get pvc -n observability
```

Render del overlay dev de ArgoCD:

```bash
kustomize build --enable-helm --load-restrictor=LoadRestrictionsNone k8s/infrastructure/overlays/dev/argocd
```

Render de la instalacion base de ArgoCD:

```bash
kustomize build --enable-helm k8s/infrastructure/base/argocd/install
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
- Las herramientas de plataforma se incorporan siguiendo el orden y el patrón
  del proyecto original. La wave 2 de observabilidad ya está desplegada con
  Helm renderizado por Kustomize y gestionado por ArgoCD.

## Estado Actual Y Siguiente Paso

El clúster local usa el perfil y contexto Minikube `openpanel-rebuild`. Las
Applications `bootstrap-app`, `argo-rollouts`, `local-path-provisioner`,
`namespaces`, `openpanel-dev`, `sealed-secrets`, `prometheus` y `alertmanager`
están `Synced`/`Healthy` en ArgoCD.

OpenPanel sigue siendo un `Deployment`; el controlador Argo Rollouts está
instalado, pero la migración de la aplicación a `Rollout` queda diferida.
Sealed Secrets está instalado, aunque aún no existe un `SealedSecret` ni una
configuración secreta consumida por OpenPanel.

La observabilidad sigue la separación del proyecto original en seis
Applications dentro de `observability`:

| Sync wave | Application | Función |
| --- | --- | --- |
| 2 | `prometheus` | Chart `kube-prometheus-stack`: Prometheus Operator, Prometheus, node exporter y kube-state-metrics; Grafana y Alertmanager integrados desactivados |
| 2 | `alertmanager` | Gestión y agrupación de alertas |
| 3 | `grafana` | Consultas, dashboards y fuentes de datos |
| 3 | `loki` | Almacenamiento y consulta de logs |
| 3 | `promtail` | Recogida de logs de pods y envío a Loki |
| 3 | `tempo` | Recepción y consulta de trazas OTLP |

Las dos Applications de wave 2 están desplegadas en `dev`, usando los charts
fijados `kube-prometheus-stack` `65.1.1` y `alertmanager` `1.13.0`, renderizados
por Kustomize. El stack recoge métricas de Kubernetes y del nodo. Alertmanager
se mantiene separado; su `ServiceMonitor` recoge sus métricas en `/metrics` y
Prometheus tiene configurado el endpoint de Alertmanager. No hay receptor de
notificaciones configurado.

En Minikube no se habilitó ingress ni un selector para nodos dedicados; las UIs
se usarán mediante `kubectl port-forward`. Los PVC de Prometheus (5 Gi) y
Alertmanager (1 Gi) están `Bound` con `local-path`.

Alertmanager apareció inicialmente `OutOfSync` porque Kubernetes añade campos
normalizados (`apiVersion`, `kind`, `metadata.creationTimestamp` y `status`) al
elemento de `volumeClaimTemplates` del StatefulSet. La Application ignora solo
esos JSON Pointers y usa `RespectIgnoreDifferences=true`; tras integrarlo,
Alertmanager quedó `Synced`/`Healthy`. El tamaño y la StorageClass del PVC
siguen siendo diferencias gestionadas por Git.

La validación de CI renderiza los dos charts de observabilidad y los incluye en
Kubeconform. La última ejecución de `ci-validate.yml` pasó. CI valida, pero no
despliega; ArgoCD sincroniza los cambios integrados en `main`.

El stack puede recoger logs de stdout/stderr de OpenPanel y métricas de
Kubernetes/nodo sin modificar la app. OpenPanel solo ofrece `/health`: no
expone `/metrics` ni emite trazas OpenTelemetry, así que sus métricas HTTP y
trazas requieren un cambio posterior de la aplicación.

Siguiente paso: preparar wave 3 (`grafana`, `loki`, `promtail` y `tempo`) con el
mismo patrón GitOps y las versiones fijadas del proyecto original. Después se
validarán dashboards y el flujo de logs/trazas. Backup y otros componentes
originales siguen pendientes. No desplegar overlays `prod` en
`openpanel-rebuild`.
