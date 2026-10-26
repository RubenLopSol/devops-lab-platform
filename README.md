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
observability         Stack de métricas, alertas, logs, trazas y dashboards
sealed-secrets        Controlador Sealed Secrets
argo-rollouts         Controlador Argo Rollouts
local-path-storage    Controlador de almacenamiento local
```

Comandos utiles:

```bash
kubectl config use-context openpanel-rebuild
kubectl get applications -n argocd
kubectl get pods -n argocd
kubectl get rollout openpanel-app -n openpanel
kubectl argo rollouts get rollout openpanel-app -n openpanel
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

grafana / loki / promtail / tempo
  watches: k8s/infrastructure/overlays/dev/observability/<component>
  applies: dashboards/data sources, logs, and traces backend

openpanel-dev
  watches: k8s/apps/overlays/dev/openpanel
  applies: OpenPanel Rollout, Services, and ConfigMap
```

Esto sigue el patron app-of-apps:

```text
bootstrap-app.yaml
   ↓ crea la Application raiz
Application/bootstrap-app
   ↓ gestiona el overlay dev de ArgoCD desde Git
AppProject/openpanel + Applications independientes
   ├── Application/openpanel-dev
   │     ↓ despliega Rollout/Services/ConfigMap en openpanel
   │     └── Pods de OpenPanel
   ├── Application/prometheus
   │     ↓ instala kube-prometheus-stack en observability
   ├── Application/alertmanager
   │     ↓ instala Alertmanager y su ServiceMonitor
   ├── Applications grafana/loki/promtail/tempo
   │     ↓ dashboards, logs y backend de trazas
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
11. Argo Rollouts actualiza OpenPanel con estrategia blue-green.
12. La app responde con el nuevo comportamiento.
```

Estado desplegado y verificado:

- Imagen/tag de la app: main-d756099
- Revisión de ArgoCD: release/platform-55e1367
- Imagen del Rollout: ghcr.io/rubenlopsol/devops-lab-app:main-d756099
- Estado: Healthy / Completed (1 réplica)


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

## Estrategia De Despliegue

OpenPanel usa Rollout de Argo Rollouts con estrategia blue-green:

- Servicio activo: openpanel-app
- Servicio preview: openpanel-app-preview
- Promoción automática: desactivada
- scaleDownDelaySeconds: 600
- Probes de salud: /health

La promoción de una nueva versión requiere revisar el preview y ejecutar
kubectl argo rollouts promote openpanel-app -n openpanel. El estado comprobado
es Healthy/Completed con una réplica lista. El nodo único de Minikube sigue
siendo un punto único de fallo.


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
kubectl get rollout openpanel-app -n openpanel -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
kubectl argo rollouts get rollout openpanel-app -n openpanel
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
  del proyecto original. Las waves 2 y 3 de observabilidad están desplegadas
  con Helm renderizado por Kustomize y gestionadas por ArgoCD.

## Estado Actual Y Pendiente

Verificado el 26-10-2026 en Minikube openpanel-rebuild: las Applications
bootstrap-app, argo-rollouts, local-path-provisioner, namespaces, openpanel-dev,
sealed-secrets, prometheus, alertmanager, grafana, loki, promtail y tempo están
Synced/Healthy.

OpenPanel usa Rollout/openpanel-app con estrategia blue-green, estado
Healthy/Completed, una réplica lista e imagen
ghcr.io/rubenlopsol/devops-lab-app:main-d756099. La Application openpanel-dev
está fijada a release/platform-55e1367. La promoción de nuevas versiones es
manual.

Grafana (chart 8.5.2, aplicación 11.2.1) responde en su API interna
(/api/health: database ok), tiene PVC de 1 Gi Bound y el SealedSecret de
credenciales se descifró a un Secret. Su configuración provisiona datasources
de Prometheus, Loki y Tempo; el dashboard de clúster está cargado en un
ConfigMap etiquetado para el sidecar. Los tres datasources se comprobaron desde Grafana: Prometheus y Loki devuelven
estado OK; la búsqueda de Tempo devuelve HTTP 200 a través del datasource.
Por eso, el datasource de Tempo se validó con una búsqueda real, que respondió correctamente. No hay
trazas de OpenPanel todavía.

La observabilidad sigue la separación del proyecto original en seis
Applications dentro de observability:

| Sync wave | Application | Función |
| --- | --- | --- |
| 2 | prometheus | Prometheus Operator, Prometheus, node exporter y kube-state-metrics |
| 2 | alertmanager | Gestión y agrupación de alertas |
| 3 | grafana | Consultas, dashboards y fuentes de datos |
| 3 | loki | Almacenamiento y consulta de logs |
| 3 | promtail | Recogida de logs de pods y envío a Loki |
| 3 | tempo | Recepción y consulta de trazas OTLP |

El chart kube-prometheus-stack tiene desactivados Grafana y Alertmanager
integrados; cada componente se gestiona como Application separada. Alertmanager
está conectado a Prometheus, pero no tiene receptor de notificaciones.

En Minikube no se habilitó ingress ni nodos dedicados; las UIs se usan mediante
kubectl port-forward. Los PVC de Prometheus (5 Gi), Alertmanager (1 Gi), Grafana
(1 Gi), Loki (10 Gi) y Tempo (1 Gi) están Bound con local-path.

El workflow de CI 40313373364 pasó el 26-10-2026, incluyendo Gitleaks y
Kubeconform para Grafana. CI valida, pero no despliega; ArgoCD sincroniza los
cambios integrados en main.

El stack recoge logs de stdout/stderr de OpenPanel y métricas del clúster/nodo.
OpenPanel no expone /metrics ni emite trazas OpenTelemetry. Tempo está instalado
y preparado, pero recibir trazas propias requiere instrumentar la aplicación.

### Backup

El backup sigue el patrón del proyecto original: Velero, un destino S3 local y
una Schedule diaria, gestionados por Applications separadas de ArgoCD. El
destino local usa RustFS (`rustfs/rustfs:1.0.3`) con API S3, PVC `local-path` de
5 Gi y el bucket `velero-backups`. Velero se instala con el chart 12.2.1
(aplicación 1.18.2) y el plugin AWS 1.14.4; usa File System Backup mediante
node-agent y no usa snapshots.

La Schedule `daily-full-backup` incluye los namespaces `openpanel` y
`observability`, corre a las 02:00 y conserva los backups 30 días. La imagen
Docker de MinIO dejó de estar disponible, por lo que se usa RustFS como
implementación S3 compatible; las credenciales selladas y el PVC mantienen sus
nombres históricos `minio-credentials` y `minio-data` para conservar el estado
local durante el cambio.

RustFS y Velero se han renderizado localmente; falta confirmar su estado vivo,
ejecutar un backup manual y probar una restauración en namespaces de prueba.
Este destino comparte el mismo clúster y disco de Minikube: sirve para aprender
y validar el flujo, pero no protege frente a la pérdida del nodo o del clúster.
No desplegar overlays prod en `openpanel-rebuild`.
