# People

API REST para consultar contribuyentes de Paraguay por número de RUC.

En la primera ejecución, la aplicación descarga los archivos de RUCs y equivalencias de la DNIT y construye una base de datos SQLite. Luego, levanta un servidor con una API REST para consultar los datos.

> [!IMPORTANT]
> Este repositorio es un fork de [blasferna/people](https://github.com/blasferna/people), creado por [Blas Isaias Fernández](https://github.com/blasferna) y publicado bajo licencia MIT. Todo el mérito del proyecto original corresponde a su autor. Este fork agrega autenticación JWT para poder exponer la API en un servidor de producción.

## Créditos y referencias

- **Proyecto original:** [github.com/blasferna/people](https://github.com/blasferna/people), de Blas Isaias Fernández (MIT).
- **Fuente de los datos:** listado público de RUC con sus equivalencias publicado por la DNIT (Dirección Nacional de Ingresos Tributarios, ex SET) en [www.set.gov.py](https://www.set.gov.py/web/portal-institucional/listado-de-ruc-con-sus-equivalencias).
- **Consumidor:** la app Android del sistema de compras usa esta API para autocompletar la razón social al registrar un proveedor.

## Cambios en este fork

- **Autenticación JWT obligatoria** (HS256) en todos los endpoints que devuelven datos: `/`, `/search`, `/ips`, `/personas`, `/names` y `/validate-ruc`.
- **Nuevo endpoint `GET /health`**, público, para verificar que el servidor está en línea.
- **Falla cerrada:** si `JWT_SECRET` no está configurado, los endpoints de datos responden `503` y no entregan información.
- **Nuevo comando `python manage.py token`** para emitir tokens firmados.
- **Corrección para Windows:** `entrypoint.sh` se normaliza a finales de línea LF (`.gitattributes` y `Dockerfile`), para que el contenedor arranque aunque el repositorio se clone en Windows.
- `.env` y `*.token` quedan excluidos de git y de la imagen Docker.

## Configuración del Entorno de Desarrollo

1. Clona el repositorio del proyecto.

```bash
git clone https://github.com/juanferreiramorel/people.git
```

2. Navega al directorio del proyecto:
    
```bash
cd people
```

3. Crea y activa un entorno virtual de Python:

```bash
python -m venv env
source env/bin/activate  # En Windows: env\Scripts\activate
```

4. Instala las dependencias del proyecto:

```bash
pip install -r requirements.txt
```

## Ejecución Local

1. Asegúrate de tener el entorno virtual activado.
2. Ejecuta el servidor web con el siguiente comando:

```bash
python manage.py runserver
```

El servidor estará disponible en `http://127.0.0.1:3000`.

> [!NOTE]
> Si es la primera vez que ejecutas el servidor, la aplicación descargará los archivos de RUCs y equivalencias de la DNIT y construirá la base de datos SQLite. Este proceso puede tardar varios minutos.

## Autenticación (JWT)

Todos los endpoints de datos exigen un token JWT en el encabezado `Authorization: Bearer <token>`.

1. Crea un archivo `.env` en la raíz del proyecto con una clave secreta larga y aleatoria. Este archivo no se sube a git.

```bash
python -c "import secrets; print('JWT_SECRET=' + secrets.token_urlsafe(48))" > .env
```

2. Emite un token para cada cliente que consuma la API:

```bash
python manage.py token --sub android-app --days 365
```

3. Envía el token en cada consulta:

```bash
curl -H "Authorization: Bearer <token>" "http://127.0.0.1:3000/?ruc=80009735"
```

| Situación | Respuesta |
|---|---|
| Token válido | `200` con los datos |
| Sin token, token inválido o firmado con otra clave | `401` `Token invalido o ausente` |
| Token vencido | `401` `Token expirado` |
| Servidor sin `JWT_SECRET` configurado | `503` `JWT_SECRET no configurado` |

Si cambias `JWT_SECRET`, todos los tokens emitidos con la clave anterior dejan de funcionar y hay que emitirlos de nuevo.

> [!WARNING]
> En producción, expón la API solo por HTTPS. Un token enviado por HTTP puede ser interceptado.

## Comandos CLI

El proyecto incluye varios comandos CLI para gestionar diferentes tareas:

- `python manage.py runserver`: Ejecuta el servidor web.
- `python manage.py build`: Vuelve a construir la base de datos. Descarga los archivos de RUCs y equivalencias y reconstruye la base de datos SQLite.
- `python manage.py download`: Descarga bases de datos preconstruidas desde URLs especificadas en las variables de entorno (opcional).
  - `RUC_DB_URL`: URL de la base de datos de RUCs preconstruida.
  - `PEOPLE_DB_URL`: URL de la base de datos de personas preconstruida.

## Despliegue

### Production (Dokploy)

The production deployment at `https://people.lanzapy.com` uses [`compose.prod.yaml`](compose.prod.yaml) as a Dokploy Compose app. See [`docs/DEPLOY.md`](docs/DEPLOY.md) for the architecture, environment variables, first deploy, token issuing, secret rotation, data refresh and rollback.

### Docker

> [!NOTE]
> The image published by the original project (`ghcr.io/blasferna/people`) does not include JWT authentication. Build the image from this repository.

The image runs as an unprivileged user (uid 1001), listens on port **3000** and refuses to start unless `JWT_SECRET` is set and at least 32 characters long.

Build the image:

```bash
docker build -t people .
```

Create a volume for the data and build the RUC database once (downloads DNIT data, takes several minutes):

```bash
docker volume create people_data
docker run --rm -v people_data:/code/data people init-data
```

Run the API with the `.env` file containing `JWT_SECRET`:

```bash
docker run -d --name people -p 3000:3000 -v people_data:/code/data --env-file .env people
```

Issue a token from the running container:

```bash
docker exec people python manage.py token --sub android-app --days 365
```

Rebuild the database later:

```bash
docker run --rm -v people_data:/code/data people build
```

Entrypoint commands: `runserver` (default), `init-data`, `build`, `download`, `token`; anything else is executed as-is. Interactive docs (`/docs`, `/openapi.json`) are disabled unless `ENABLE_DOCS=true`.

## Endpoints

Todos los endpoints de datos requieren el encabezado `Authorization: Bearer <token>` (ver [Autenticación (JWT)](#autenticación-jwt)).

### Estado del servidor (público)

```bash
curl 'http://127.0.0.1:3000/health'
```

Respuesta:

```json
{"status": "ok"}
```

### Obtener datos de RUC por número

El número se envía sin el dígito verificador (DV).

```bash
curl -X 'GET' \
  'http://127.0.0.1:3000/?ruc=80009735' \
  -H 'accept: application/json' \
  -H 'Authorization: Bearer <token>'
```

Respuesta:

```json
{
  "ruc": "80009735",
  "razonsocial": "ADMINISTRACION NACIONAL DE ELECTRICIDAD - ANDE",
  "tipo": "J",
  "categoria": "GRANDE",
  "dv": "1",
  "estado": "ACTIVO"
}
```

### Búsqueda por número de RUC o nombre de contribuyente

```bash
curl -X 'GET' \
  'http://127.0.0.1:3000/search?query=80009735' \
  -H 'accept: application/json' \
  -H 'Authorization: Bearer <token>'
```

Respuesta:

```json
[
  {
    "ruc": "80009735",
    "razonsocial": "ADMINISTRACION NACIONAL DE ELECTRICIDAD - ANDE",
    "tipo": "J",
    "categoria": "GRANDE",
    "dv": "1",
    "estado": "ACTIVO"
  }
]
```
