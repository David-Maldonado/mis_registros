# DATA_MODEL.md

**Proyecto:** MisRegistros  
**Versión:** 1.3  
**Estado:** Diseño técnico cerrado, pendiente de implementación y pruebas  
**Base de datos:** Supabase PostgreSQL

---

## 1. Objetivo y alcance

Este documento define el modelo de datos de MisRegistros para su primera versión.

Establece:

- Las entidades y sus relaciones.
- La estructura de las tablas.
- Las reglas de integridad financiera.
- Las restricciones y los triggers.
- La seguridad, los permisos y las políticas RLS.
- Las funciones RPC para las operaciones de escritura.
- La concurrencia y los bloqueos.
- Los índices y criterios de consulta.
- La eliminación segura de los datos de un usuario.

El modelo contempla seis tablas propias y la tabla `auth.users`, administrada por Supabase Auth.

Las decisiones aquí documentadas constituyen la referencia para las migraciones SQL y la implementación del backend.

### 1.1. Alcance funcional de V1

- Registro, autenticación y gestión básica del perfil.
- Cuentas de efectivo, bancos, billeteras y tarjetas de crédito.
- Ingresos y gastos.
- Transferencias entre cuentas.
- Pagos de tarjetas de crédito.
- Devoluciones parciales.
- Ajustes de saldo.
- Edición de operaciones mediante reemplazo atómico y eliminación mediante anulación.
- Categorías y subcategorías personalizables, creadas por cada usuario.
- Historial de movimientos.
- Resúmenes y balances mensuales calculados en la zona horaria del usuario.
- Soporte para PYG y USD.
- Aislamiento de datos entre usuarios.

### 1.2. Fuera del alcance de V1

- Cuentas compartidas.
- Grupos familiares.
- Gastos compartidos entre usuarios.
- Conversión automática de monedas.
- Cuotas y financiación de tarjetas.
- Fechas de cierre y vencimiento de tarjetas.
- Reportes financieros avanzados.

---

## 2. Principios del modelo

1. Cada usuario administra exclusivamente sus propios datos.
2. Todas las entidades propias utilizan identificadores UUID.
3. Los importes monetarios utilizan `numeric(18,4)`.
4. Las fechas se almacenan como `timestamptz`.
5. Los estados y tipos se representan mediante `text` y restricciones `CHECK`.
6. Los importes de las transacciones son siempre positivos.
7. Los movimientos de cuenta utilizan importes con signo.
8. Los saldos se calculan a partir del saldo inicial y los movimientos contabilizados.
9. Las transacciones contabilizadas no se eliminan físicamente durante la operación normal.
10. Las correcciones financieras se realizan mediante anulaciones y nuevas operaciones.
11. Las devoluciones conservan una referencia al gasto original.
12. Las escrituras se realizan mediante funciones RPC controladas.
13. Las lecturas respetan RLS y la propiedad de los datos.
14. La base de datos debe mantener las reglas financieras incluso cuando las solicitudes lleguen directamente desde una sesión autenticada.
15. Las cuentas líquidas nunca pueden quedar con saldo negativo; las tarjetas de crédito sí, porque su saldo negativo representa deuda.
16. Los períodos mensuales se determinan según la zona horaria del usuario, no según UTC.
17. Las operaciones de creación de transacciones son idempotentes: un reintento de la misma solicitud no genera duplicados.

---

## 3. Modelo entidad-relación

Entidades:

- `auth.users`
- `profiles`
- `currencies`
- `accounts`
- `categories`
- `transactions`
- `account_movements`

Relaciones principales:

- Un usuario tiene un perfil.
- Un usuario puede tener múltiples cuentas.
- Un usuario puede tener múltiples categorías.
- Una categoría puede tener subcategorías.
- Un usuario puede registrar múltiples transacciones.
- Una transacción puede generar uno o dos movimientos de cuenta.
- Una devolución referencia un gasto original.
- Una transacción corregida puede referenciar a la transacción anulada que reemplaza.
- Una cuenta puede contener múltiples movimientos.
- Cada cuenta y transacción utiliza una moneda.

La propiedad de los registros se determina mediante `user_id`, y las claves foráneas compuestas impiden relacionar registros pertenecientes a usuarios o monedas diferentes.

Las columnas `user_id` de las tablas de dominio referencian `profiles(id)`, no `auth.users(id)`. De este modo, `profiles` es la raíz de los datos de cada usuario y la eliminación de una cuenta de Supabase Auth sigue una única cadena controlada: `auth.users → profiles → purga de datos` (ver sección 12).

---

## 4. Entidades

### 4.1. profiles

Extiende la información del usuario autenticado.

| Campo | Tipo | Restricción |
|---|---|---|
| id | uuid | PK, FK a auth.users(id), ON DELETE CASCADE |
| display_name | text | NULL permitido |
| default_currency_id | uuid | FK a currencies(id), NOT NULL |
| timezone | text | NOT NULL DEFAULT 'America/Asuncion' |
| created_at | timestamptz | NOT NULL |
| updated_at | timestamptz | NOT NULL |

Reglas:

- Se crea automáticamente al registrarse un usuario.
- `id` coincide con `auth.users.id`.
- La moneda por defecto inicial es PYG.
- La zona horaria inicial es `America/Asuncion`.
- `timezone` debe ser un identificador IANA válido (existente en `pg_timezone_names`); se valida en la RPC de actualización.
- `timezone` se utiliza para determinar los límites de los períodos mensuales en los resúmenes.
- No se crean categorías por defecto al registrarse: cada usuario crea las suyas.
- El usuario solo puede consultar y modificar su propio perfil.
- La actualización del perfil se realiza mediante RPC.
- La eliminación del usuario desencadena la purga controlada de sus datos.

### 4.2. currencies

Catálogo global de monedas.

| Campo | Tipo | Restricción |
|---|---|---|
| id | uuid | PK |
| code | text | UNIQUE, NOT NULL |
| name | text | NOT NULL |
| symbol | text | NOT NULL |
| decimal_places | smallint | NOT NULL, CHECK 0–4 |
| is_active | boolean | NOT NULL DEFAULT true |
| created_at | timestamptz | NOT NULL |

Monedas iniciales:

| Código | Nombre | Símbolo | Decimales |
|---|---|---|---:|
| PYG | Guaraní paraguayo | ₲ | 0 |
| USD | Dólar estadounidense | $ | 2 |

Reglas:

- `code` debe cumplir `^[A-Z]{3}$`.
- El código y la precisión decimal no se modifican una vez que la moneda está en uso.
- Las monedas utilizadas no se eliminan.
- `is_active` permite impedir su utilización en nuevas operaciones.
- Los datos históricos conservan su moneda original.
- La carga inicial y las modificaciones del catálogo corresponden exclusivamente a migraciones o administración privilegiada.

### 4.3. accounts

Representa las cuentas financieras del usuario.

| Campo | Tipo | Restricción |
|---|---|---|
| id | uuid | PK |
| user_id | uuid | FK a profiles(id), NOT NULL |
| currency_id | uuid | FK a currencies(id), NOT NULL |
| name | text | NOT NULL |
| type | text | NOT NULL |
| initial_balance | numeric(18,4) | NOT NULL DEFAULT 0 |
| credit_limit | numeric(18,4) | NULL |
| is_active | boolean | NOT NULL DEFAULT true |
| created_at | timestamptz | NOT NULL |
| updated_at | timestamptz | NOT NULL |

Tipos permitidos:

- `cash`
- `bank`
- `e_wallet`
- `credit_card`

Restricciones:

- `UNIQUE (id, user_id, currency_id)`.
- `name` no puede estar vacío.
- `initial_balance` debe ser mayor o igual a cero para cuentas líquidas.
- `initial_balance` debe ser menor o igual a cero para tarjetas de crédito.
- `credit_limit` debe ser positivo exclusivamente para `credit_card`.
- Para el resto de los tipos, `credit_limit` debe ser NULL.

Reglas de modificación:

- `currency_id` y `type` son inmutables después de crear la cuenta.
- `initial_balance` solo puede modificarse mientras no existan movimientos asociados.
- `credit_limit` puede modificarse únicamente en cuentas de tipo `credit_card`.
- El nombre y el estado pueden modificarse mediante RPC.
- Una cuenta utilizada no se elimina; se desactiva.
- Una cuenta nunca utilizada puede eliminarse si no tiene dependencias.

Convención de saldos:

- Cuenta líquida: saldo positivo representa dinero disponible.
- Cuenta líquida: el saldo nunca puede ser negativo (no se admite sobregiro en V1).
- Tarjeta: saldo negativo representa deuda.
- Tarjeta con saldo cero: deuda cancelada.
- Tarjeta con saldo positivo: crédito a favor.
- Tarjeta: los gastos se registran siempre, aunque el usuario no tenga saldo en sus cuentas líquidas.

La interfaz presenta la deuda de la tarjeta como un valor positivo, aunque internamente se almacena como saldo negativo.

El límite de crédito es informativo: no impide registrar gastos que lo superen. La interfaz puede advertir al usuario cuando la deuda supera el límite (crédito disponible negativo).

### 4.4. categories

Representa las categorías y subcategorías personalizables.

| Campo | Tipo | Restricción |
|---|---|---|
| id | uuid | PK |
| user_id | uuid | FK a profiles(id), NOT NULL |
| parent_id | uuid | NULL |
| name | text | NOT NULL |
| type | text | NOT NULL |
| is_active | boolean | NOT NULL DEFAULT true |
| created_at | timestamptz | NOT NULL |
| updated_at | timestamptz | NOT NULL |

Tipos permitidos:

- `income`
- `expense`

Restricciones:

- `UNIQUE (id, user_id)`.
- `UNIQUE (id, user_id, type)`.
- `parent_id` referencia otra categoría del mismo usuario y del mismo tipo.
- Una categoría padre no puede ser a su vez una subcategoría.
- La jerarquía admite como máximo dos niveles.
- Los nombres de categorías hermanas deben ser únicos sin distinguir mayúsculas y minúsculas, después de aplicar `btrim`.
- Una categoría no puede estar vacía.

Reglas:

- Una categoría utilizada no puede cambiar de tipo.
- Una categoría utilizada no puede cambiar de padre.
- Una categoría raíz que tenga subcategorías no puede convertirse en subcategoría.
- Una categoría utilizada o que tenga subcategorías se desactiva en lugar de eliminarse.
- Una categoría nunca utilizada y sin dependencias puede eliminarse.
- Una categoría inactiva no puede utilizarse en nuevas operaciones que requieran seleccionar una categoría.
- Las operaciones históricas conservan su referencia a la categoría.
- El sistema no crea categorías predefinidas. Un usuario sin categorías activas del tipo requerido no puede registrar ingresos o gastos hasta crear al menos una; la interfaz debe guiarlo para hacerlo.

### 4.5. transactions

Representa las operaciones financieras.

| Campo | Tipo | Restricción |
|---|---|---|
| id | uuid | PK |
| user_id | uuid | FK a profiles(id), NOT NULL |
| client_request_id | uuid | NOT NULL |
| type | text | NOT NULL |
| status | text | NOT NULL DEFAULT 'posted' |
| currency_id | uuid | FK a currencies(id), NOT NULL |
| amount | numeric(18,4) | NOT NULL |
| category_id | uuid | NULL |
| related_transaction_id | uuid | NULL |
| replaces_transaction_id | uuid | NULL |
| occurred_at | timestamptz | NOT NULL |
| description | text | NULL |
| voided_at | timestamptz | NULL |
| void_reason | text | NULL |
| created_at | timestamptz | NOT NULL |
| updated_at | timestamptz | NOT NULL |

Tipos permitidos:

- `income`
- `expense`
- `transfer`
- `refund`
- `adjustment`

Estados permitidos:

- `posted`
- `voided`

Restricciones:

- `amount > 0`.
- `UNIQUE (id, user_id, currency_id)`.
- `income` y `expense` requieren categoría del tipo correspondiente.
- `refund` requiere categoría y referencia al gasto original.
- `transfer` y `adjustment` no utilizan categoría.
- `related_transaction_id` solo se permite para `refund`.
- La referencia de una devolución debe corresponder a una transacción del mismo usuario y moneda.
- `voided_at` debe ser NULL cuando el estado es `posted`.
- `voided_at` debe tener valor cuando el estado es `voided`.
- `void_reason` solo se utiliza en transacciones anuladas.
- `UNIQUE (user_id, client_request_id)`.
- `replaces_transaction_id` referencia una transacción del mismo usuario y del mismo tipo, que debe quedar `voided`.
- Una transacción solo puede ser reemplazada una vez (`UNIQUE (replaces_transaction_id)` parcial, cuando no es NULL).

Reglas de modificación:

- `occurred_at`, `type`, `currency_id`, `amount`, `category_id`, `related_transaction_id`, `replaces_transaction_id` y `client_request_id` son inmutables después de contabilizar la operación.
- La descripción puede modificarse.
- La única transición de estado permitida es `posted → voided`.
- Una transacción anulada no puede volver a contabilizarse.
- Las transacciones contabilizadas no pueden eliminarse físicamente mediante operaciones normales.
- La corrección de una operación se realiza mediante reemplazo atómico: se anula la original y se crea la corregida en la misma transacción PostgreSQL (ver sección 6.10).
- La "eliminación" visible para el usuario corresponde a una anulación.

Idempotencia:

- `client_request_id` es un UUID generado por el cliente para cada intención de operación.
- Si llega una solicitud con un `client_request_id` ya registrado para el usuario, la RPC devuelve la transacción existente sin crear otra.
- Si el `client_request_id` coincide pero los parámetros son diferentes, la RPC rechaza la solicitud.

### 4.6. account_movements

Representa el impacto de una transacción sobre una cuenta.

| Campo | Tipo | Restricción |
|---|---|---|
| id | uuid | PK |
| user_id | uuid | NOT NULL |
| transaction_id | uuid | NOT NULL |
| account_id | uuid | NOT NULL |
| currency_id | uuid | NOT NULL |
| signed_amount | numeric(18,4) | NOT NULL |
| occurred_at | timestamptz | NOT NULL |
| created_at | timestamptz | NOT NULL |

Restricciones:

- `signed_amount <> 0`.
- `UNIQUE (transaction_id, account_id)`.
- La transacción debe pertenecer al mismo usuario y moneda.
- La cuenta debe pertenecer al mismo usuario y moneda.
- Los movimientos son inmutables durante la operación normal.
- No se permite UPDATE ni DELETE desde las funciones ordinarias.

Los movimientos conservan el impacto histórico de las operaciones, incluso después de su anulación.

---

## 5. Relaciones y claves foráneas

Las siguientes relaciones utilizan claves foráneas compuestas:

| Tabla origen | Columnas | Tabla destino | Columnas |
|---|---|---|---|
| categories | parent_id, user_id, type | categories | id, user_id, type |
| transactions | category_id, user_id | categories | id, user_id |
| transactions | related_transaction_id, user_id, currency_id | transactions | id, user_id, currency_id |
| transactions | replaces_transaction_id, user_id, type | transactions | id, user_id, type |
| account_movements | transaction_id, user_id, currency_id | transactions | id, user_id, currency_id |
| account_movements | account_id, user_id, currency_id | accounts | id, user_id, currency_id |

Para soportar la última relación de `transactions`, se agrega la restricción `UNIQUE (id, user_id, type)` en `transactions`.

Además, `accounts.user_id`, `categories.user_id` y `transactions.user_id` referencian `profiles(id)`. `account_movements.user_id` queda vinculado al usuario mediante sus claves compuestas hacia `transactions` y `accounts`.

Las relaciones financieras utilizan `ON DELETE NO ACTION` (comportamiento por defecto), excepto la relación entre `profiles` y `auth.users`, que utiliza `ON DELETE CASCADE`.

Se elige `NO ACTION` en lugar de `RESTRICT` porque:

- En la operación normal ambas impiden eliminar un registro referenciado.
- `NO ACTION` verifica la restricción al final de la sentencia, lo que permite que la purga elimine en una única sentencia filas que se referencian entre sí (devoluciones, reemplazos y subcategorías).
- `RESTRICT` verifica cada fila inmediatamente y haría fallar esas eliminaciones según el orden interno en que PostgreSQL procese las filas.

La purga de usuario controla el orden de eliminación de los registros dependientes.

---

## 6. Reglas financieras

### 6.1. Cálculo de saldos

El saldo de una cuenta se calcula mediante:

`initial_balance + SUM(account_movements.signed_amount)`

Solo se consideran movimientos cuya transacción tenga estado `posted`.

Los movimientos de transacciones `voided` se conservan, pero no afectan el saldo.

Los saldos no se almacenan como valores independientes que puedan desincronizarse de los movimientos.

Regla de saldo no negativo:

- Ninguna operación puede dejar una cuenta líquida con saldo negativo.
- La regla se aplica a gastos, transferencias de origen, ajustes negativos, anulaciones y reemplazos.
- Una anulación que reduzca el saldo de una cuenta líquida (por ejemplo, anular un ingreso ya gastado) se rechaza si dejaría la cuenta en negativo.
- Las tarjetas de crédito no están sujetas a esta regla.

El crédito disponible de una tarjeta se calcula como `credit_limit + saldo`. Es un valor informativo y puede ser negativo.

### 6.2. Ingresos

- Una transacción de tipo `income`.
- Un único movimiento positivo.
- La cuenta debe ser líquida.
- La categoría debe ser de tipo `income`.

### 6.3. Gastos

- Una transacción de tipo `expense`.
- Un único movimiento negativo.
- La cuenta puede ser líquida o tarjeta de crédito.
- Si la cuenta es líquida, debe tener saldo suficiente.
- Si la cuenta es tarjeta, el gasto se registra aunque supere el límite de crédito.
- La categoría debe ser de tipo `expense`.

### 6.4. Transferencias

- Una transacción de tipo `transfer`.
- Dos movimientos.
- Una cuenta de origen y una de destino diferentes.
- Ambos movimientos deben tener la misma moneda.
- La suma de ambos movimientos debe ser cero.
- El movimiento de origen es negativo.
- El movimiento de destino es positivo.
- La cuenta de origen debe tener saldo suficiente.

Combinaciones permitidas:

- Líquida → líquida.
- Líquida → tarjeta de crédito.

No se permiten en V1:

- Transferencias entre monedas diferentes.
- Transferencias desde una tarjeta de crédito (avances de efectivo).

Las transferencias se registran siempre como salida de la cuenta de origen y entrada en la cuenta de destino, y aparecen en el historial y en el flujo de cada cuenta. No se suman a los totales de ingresos y gastos del resumen mensual, porque mover dinero entre cuentas propias no es un ingreso ni un gasto (ver sección 6.11).

### 6.5. Pagos de tarjetas

El pago de una tarjeta se representa como una transferencia:

- Salida negativa de la cuenta líquida.
- Entrada positiva en la tarjeta.
- La deuda de la tarjeta disminuye.
- El pago no genera un nuevo gasto.

### 6.6. Devoluciones

- Una transacción de tipo `refund`.
- Un único movimiento positivo.
- La cuenta puede ser líquida o tarjeta de crédito.
- Debe referenciar un gasto original `posted`.
- El gasto original debe pertenecer al mismo usuario.
- Debe utilizar la misma moneda.
- La categoría debe ser exactamente la del gasto original.
- Puede recibirse en una cuenta diferente de la utilizada para el gasto.
- La cuenta receptora debe estar activa.

Se permiten múltiples devoluciones parciales.

La suma de devoluciones contabilizadas no puede superar el importe del gasto original.

Para garantizarlo ante solicitudes concurrentes, la función `create_refund` debe bloquear la fila del gasto original mediante `SELECT ... FOR UPDATE`, calcular el acumulado de devoluciones `posted` y validar el importe restante antes de insertar la nueva devolución.

Las devoluciones reducen los gastos netos del período en el que se reciben, no del período en que se realizó el gasto original.

Los informes deben poder distinguir:

- Gastos brutos.
- Devoluciones recibidas.
- Gastos netos.

### 6.7. Ajustes

- Una transacción de tipo `adjustment`.
- Un único movimiento.
- El movimiento puede ser positivo o negativo.
- Puede afectar cualquier tipo de cuenta.
- No requiere categoría.
- Un ajuste negativo no puede dejar una cuenta líquida con saldo negativo.
- Los ajustes no se suman a los totales de ingresos y gastos; se muestran por separado en el resumen.

### 6.8. Cuentas y operaciones inactivas

Todas las cuentas involucradas en una nueva operación deben estar activas.

Las categorías requeridas para ingresos y gastos deben estar activas.

La desactivación no altera el historial ni los saldos existentes.

### 6.9. Anulaciones

- Una transacción `posted` puede pasar a `voided`.
- La operación es irreversible.
- Los movimientos no se eliminan ni modifican.
- Los movimientos de una operación anulada dejan de participar en el cálculo de saldos.
- Una transacción anulada no puede volver a contabilizarse.
- No se permite anular un gasto mientras tenga devoluciones contabilizadas.
- Para anular un gasto con devoluciones, primero deben anularse las devoluciones correspondientes.
- La anulación de una devolución libera el importe que vuelve a estar disponible para devolver.
- No se permite una anulación que deje una cuenta líquida con saldo negativo.

### 6.10. Edición mediante reemplazo

La edición de una operación se implementa como un reemplazo atómico:

1. Se bloquea la transacción original.
2. Se verifica que pertenece al usuario y que está `posted`.
3. Se anula la original con `void_reason = 'replaced'`.
4. Se crea una nueva transacción del mismo tipo con los datos corregidos y `replaces_transaction_id` apuntando a la original.
5. Ambas acciones se confirman o se revierten juntas.

Reglas:

- El tipo de operación no cambia. Para cambiar el tipo, el usuario anula y crea una nueva operación.
- Pueden modificarse importe, cuentas, categoría, fecha y descripción, respetando las reglas del tipo.
- La moneda resulta de las cuentas elegidas, que deben compartir moneda cuando corresponda.
- El reemplazo de una devolución debe referenciar el mismo gasto original.
- No se puede reemplazar un gasto con devoluciones contabilizadas, por la misma regla que impide anularlo.
- Las validaciones de saldo no negativo se evalúan sobre el estado final, después de anular y crear.
- El historial conserva la operación original anulada y su vínculo con la corregida.

### 6.11. Resúmenes mensuales

Los resúmenes se calculan por moneda, sin sumar importes de monedas diferentes, y solo con transacciones `posted`.

El mes se determina convirtiendo `occurred_at` a la zona horaria del perfil del usuario (`profiles.timezone`). Por ejemplo, un gasto realizado el 31/10 a las 23:00 en Paraguay se guarda como 01/11 02:00 UTC, pero corresponde a octubre.

Indicadores:

| Indicador | Cálculo |
|---|---|
| Ingresos | Suma de `income` |
| Gastos brutos | Suma de `expense` |
| Devoluciones | Suma de `refund` |
| Gastos netos | Gastos brutos − devoluciones |
| Balance mensual | Ingresos − gastos netos |
| Transferencias | Total transferido entre cuentas propias, informado por separado |
| Ajustes | Suma de ajustes positivos y negativos, informados por separado |

Las transferencias y los ajustes no se incluyen en ingresos, gastos ni balance mensual.

Flujo por cuenta:

- Para cada cuenta se informan las entradas y salidas del período, incluyendo todos los tipos de operación (ingresos, gastos, transferencias, devoluciones y ajustes).
- Así, toda entrada o salida de dinero queda registrada y visible, sin duplicar los totales de ingresos y gastos.

---

## 7. Integridad declarativa y triggers

### 7.1. Restricciones CHECK

Implementar restricciones para:

- Tipos y estados permitidos.
- Importes positivos en `transactions`.
- Importes distintos de cero en `account_movements`.
- Signo permitido de `initial_balance`.
- Condiciones de `credit_limit`.
- Categoría requerida según el tipo de transacción.
- Referencia obligatoria para devoluciones.
- Referencia prohibida para otros tipos.
- Coherencia de `voided_at` y `void_reason`.
- Formato de códigos de moneda.
- Precisión decimal permitida por moneda.

### 7.2. Triggers de timestamps

Implementar una función reutilizable `set_updated_at()`.

Aplicarla a:

- `profiles`
- `accounts`
- `categories`
- `transactions`

El valor de `updated_at` será administrado por PostgreSQL, no por el cliente.

### 7.3. Creación automática del perfil

Crear un trigger `AFTER INSERT` sobre `auth.users`.

La función:

- Se ejecuta como `SECURITY DEFINER`.
- Tiene propietario privilegiado de confianza.
- Utiliza `SET search_path = pg_catalog, public, pg_temp`.
- Inserta el perfil correspondiente, con moneda por defecto PYG y zona horaria `America/Asuncion`.
- No crea categorías ni cuentas.
- No acepta un `user_id` proporcionado por el cliente.

Un error en esta función impide el registro del usuario, por lo que debe ser simple y estar cubierta por pruebas.

La función no debe exponerse como RPC pública.

### 7.4. Validación de cuentas

Implementar un trigger de ciclo de vida que impida:

- Modificar el tipo de cuenta.
- Modificar la moneda.
- Cambiar el saldo inicial después de existir movimientos.
- Asignar un límite de crédito a una cuenta que no sea tarjeta.
- Eliminar una cuenta utilizada.

Las validaciones se aplican incluso cuando la operación se realiza desde una función RPC.

### 7.5. Validación de categorías

Implementar un trigger que garantice:

- Máximo dos niveles.
- Padre del mismo usuario y tipo.
- El padre debe ser una categoría raíz.
- Una categoría con hijos no puede convertirse en subcategoría.
- El tipo no cambia cuando existen transacciones o subcategorías.
- El padre no cambia cuando la categoría ya fue utilizada.
- Una categoría utilizada no puede eliminarse.

La unicidad de nombres de categorías hermanas se implementa mediante índices únicos parciales sobre `lower(btrim(name))`, diferenciando categorías raíz y subcategorías.

### 7.6. Inmutabilidad de transacciones

Implementar un trigger que permita exclusivamente:

- Modificar la descripción de una transacción `posted`.
- Cambiar de `posted` a `voided`, con sus campos de anulación.
- Eliminar durante la purga controlada de un usuario.

No permitir:

- Modificar importes.
- Modificar monedas.
- Modificar tipos.
- Modificar fechas de contabilización.
- Cambiar categorías.
- Cambiar referencias financieras.
- Reactivar transacciones anuladas.

El trigger debe ser `SECURITY INVOKER`.

Para el borrado durante la purga, comprobar que `current_user` corresponde al rol dedicado `app_user_purger`.

No utilizar una variable GUC como mecanismo de autorización.

### 7.7. Inmutabilidad de movimientos

Implementar un trigger que:

- Rechace cualquier UPDATE.
- Rechace cualquier DELETE ordinario.
- Permita DELETE exclusivamente cuando `current_user` sea `app_user_purger`.

El trigger debe ser `SECURITY INVOKER`.

### 7.8. Validación diferida de movimientos

Implementar un constraint trigger diferible al final de la transacción, asociado a `transactions` y `account_movements`.

Debe verificar:

| Tipo | Cantidad de movimientos |
|---|---:|
| income | 1 |
| expense | 1 |
| refund | 1 |
| adjustment | 1 |
| transfer | 2 |

Además debe verificar:

- Relación entre importe de transacción y movimientos.
- Signos correctos.
- Suma cero en transferencias.
- Cuentas distintas en transferencias.
- Matriz permitida de tipos de cuenta.
- Correspondencia de usuario y moneda.
- Correspondencia de `occurred_at`.
- Categoría correspondiente al tipo.
- Categoría heredada del gasto original en devoluciones.
- Existencia y estado válido del gasto original.
- Límite acumulado de devoluciones contabilizadas.
- Saldo no negativo de las cuentas líquidas afectadas, incluso cuando el evento es una anulación.
- Coherencia del reemplazo: la transacción reemplazada es del mismo tipo y quedó `voided`.

Para una transacción anulada, los movimientos deben seguir existiendo y conservar su estructura original.

En eventos de eliminación durante la purga, la validación diferida debe reconocer que la transacción ya no existe y no intentar validar una operación eliminada. Las claves foráneas continúan protegiendo las relaciones durante las operaciones normales.

---

## 8. Seguridad, permisos y RLS

### 8.1. Arquitectura de acceso

Flujo de la aplicación:

`Flutter → NestJS → Supabase`

Responsabilidades:

**Flutter**
- Interfaz y experiencia de usuario.
- Autenticación mediante Supabase Auth.
- Envío de solicitudes al backend.
- No contiene secretos privilegiados.

**NestJS**
- Valida los JWT emitidos por Supabase.
- Obtiene la identidad del usuario exclusivamente del token validado.
- Ejecuta validaciones de entrada y reglas de aplicación.
- Invoca las funciones RPC.
- Gestiona las respuestas y errores.

**PostgreSQL**
- Garantiza integridad referencial.
- Aplica RLS.
- Protege las reglas financieras.
- Ejecuta operaciones atómicas.
- Impide modificaciones históricas no permitidas.

La clave publicable de Supabase no es un secreto. La seguridad no debe depender de ocultarla ni de asumir que Flutter no puede llamar directamente a PostgREST.

### 8.2. Roles de base de datos

#### authenticated

Rol utilizado por las sesiones de usuarios autenticados.

Características:

- No es propietario de las tablas.
- No tiene `BYPASSRLS`.
- No puede crear objetos en el esquema `public`.
- Tiene permisos de lectura limitados por RLS.
- Puede ejecutar exclusivamente las RPC autorizadas.

No dispone de permisos DML ordinarios sobre las tablas financieras ni sobre cuentas, categorías o perfiles.

#### app_ledger_writer

Rol dedicado a ejecutar las funciones RPC de escritura.

Características:

- `NOLOGIN`
- `NOSUPERUSER`
- `NOCREATEDB`
- `NOCREATEROLE`
- `NOINHERIT`
- `NOBYPASSRLS`

No es propietario de las tablas.

Tiene únicamente los permisos necesarios para ejecutar las operaciones de escritura:

- SELECT sobre las tablas necesarias.
- INSERT y UPDATE sobre las tablas correspondientes.
- DELETE limitado a cuentas y categorías nunca utilizadas, sujeto a restricciones referenciales.
- INSERT sobre `transactions` y `account_movements`.
- UPDATE controlado sobre `transactions`.
- UPDATE limitado sobre `profiles`, `accounts` y `categories`.

No tiene DELETE sobre `transactions` ni `account_movements`.

Las funciones RPC privilegiadas son propiedad de este rol.

No se concede membresía de este rol a `authenticated` ni a `anon`.

#### app_user_purger

Rol dedicado exclusivamente a la purga de los datos de un usuario.

Características:

- `NOLOGIN`
- `NOSUPERUSER`
- `NOCREATEDB`
- `NOCREATEROLE`
- `NOINHERIT`
- `NOBYPASSRLS`

No tiene membresías concedidas a roles de aplicación.

Dispone de los permisos mínimos necesarios para:

- Consultar las filas involucradas en la purga.
- Eliminar movimientos.
- Eliminar transacciones.
- Eliminar cuentas.
- Eliminar categorías.

Las políticas RLS específicas para este rol permiten esas operaciones durante la ejecución de la función de purga.

La función `trg_profiles_purge_user_data` es `SECURITY DEFINER` y su propietario es `app_user_purger`.

La función no se expone como RPC ni se concede EXECUTE a los usuarios de la aplicación.

Los triggers de inmutabilidad identifican el contexto de purga mediante `current_user`, sin depender de parámetros personalizados de sesión.

### 8.3. RLS

Activar RLS y `FORCE ROW LEVEL SECURITY` en todas las tablas propias que contienen datos de usuario:

- profiles
- accounts
- categories
- transactions
- account_movements

La tabla `currencies` es un catálogo global de lectura.

Políticas para usuarios autenticados:

| Tabla | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| profiles | Propio perfil | No | No | No |
| accounts | Propias cuentas | No | No | No |
| categories | Propias categorías | No | No | No |
| transactions | Propias transacciones | No | No | No |
| account_movements | Propios movimientos | No | No | No |
| currencies | Catálogo global | No | No | No |

Las políticas de propiedad utilizan:

- `profiles.id = auth.uid()`
- `user_id = auth.uid()` para las demás tablas de usuario.

El rol `app_ledger_writer` dispone de políticas compatibles con las operaciones de escritura, limitadas a filas cuyo `user_id` coincide con `auth.uid()`.

Para `profiles`, la condición es `id = auth.uid()`.

El rol `app_user_purger` dispone de políticas específicas para las operaciones de purga. No se le concede `BYPASSRLS`.

### 8.4. Matriz de privilegios

| Tabla | authenticated | app_ledger_writer | app_user_purger |
|---|---|---|---|
| profiles | SELECT | SELECT, UPDATE limitado | Solo lo estrictamente necesario |
| currencies | SELECT | SELECT | Sin acceso ordinario |
| accounts | SELECT | SELECT, INSERT, UPDATE, DELETE controlado | SELECT, DELETE |
| categories | SELECT | SELECT, INSERT, UPDATE, DELETE controlado | SELECT, DELETE |
| transactions | SELECT | SELECT, INSERT, UPDATE controlado | SELECT, DELETE |
| account_movements | SELECT | SELECT, INSERT | SELECT, DELETE |

Los permisos deben implementarse mediante `GRANT` y `REVOKE` explícitos.

Revocar privilegios de escritura de `PUBLIC`, `anon` y `authenticated` sobre las tablas de dominio.

Los permisos del rol purgador no deben heredarse ni estar disponibles para sesiones ordinarias.

### 8.5. Funciones SECURITY DEFINER

Todas las funciones privilegiadas deben:

- Tener propietario explícito.
- Utilizar `SET search_path = pg_catalog, public, pg_temp`.
- Referenciar objetos mediante nombres calificados cuando corresponda.
- Evitar SQL dinámico innecesario.
- Validar `auth.uid()` antes de operar.
- No aceptar `user_id` como fuente de identidad del usuario.
- Tener EXECUTE revocado para `PUBLIC` y `anon`.
- Conceder EXECUTE exclusivamente a `authenticated` cuando corresponda.

El esquema `public` no debe permitir que roles no confiables creen objetos.

Las funciones de trigger internas no deben exponerse como RPC.

La propiedad de tablas y migraciones permanece en el rol administrativo de despliegue, separado de los roles de ejecución de la aplicación.

---

## 9. Funciones RPC

Todas las escrituras de la aplicación se realizan mediante funciones RPC.

Las funciones financieras se ejecutan de forma atómica dentro de una transacción PostgreSQL.

### 9.1. Operaciones financieras

| Función | Responsabilidad |
|---|---|
| create_income | Crear un ingreso y su movimiento |
| create_expense | Crear un gasto y su movimiento |
| create_transfer | Crear transferencia y sus dos movimientos |
| create_refund | Crear devolución parcial |
| create_adjustment | Crear ajuste de saldo |
| replace_transaction | Editar una operación mediante reemplazo atómico |
| update_transaction_description | Actualizar descripción |
| void_transaction | Anular transacción |

Las funciones `create_*` y `replace_transaction` reciben el parámetro `p_client_request_id` para garantizar la idempotencia.

Cada función debe:

1. Obtener `auth.uid()`.
2. Rechazar solicitudes sin usuario autenticado.
3. Validar los parámetros y, cuando corresponda, resolver la idempotencia.
4. Validar la propiedad de los registros.
5. Bloquear las filas necesarias.
6. Validar cuentas, categorías, moneda y estado.
7. Insertar o actualizar los registros.
8. Permitir que los triggers diferidos validen la operación.
9. Devolver el resultado de la operación.

### 9.2. Administración de cuentas

| Función | Responsabilidad |
|---|---|
| create_account | Crear cuenta |
| update_account | Modificar campos permitidos |
| delete_account | Eliminar cuenta nunca utilizada |

`update_account` solo permite modificar:

- name
- initial_balance, si no existen movimientos
- credit_limit, cuando corresponda
- is_active

No permite modificar `user_id`, `currency_id` ni `type`.

### 9.3. Administración de categorías

| Función | Responsabilidad |
|---|---|
| create_category | Crear categoría o subcategoría |
| update_category | Modificar campos permitidos |
| delete_category | Eliminar categoría sin dependencias |

Las funciones deben respetar la jerarquía, el tipo y las restricciones de uso.

### 9.4. Administración del perfil

| Función | Responsabilidad |
|---|---|
| update_profile | Actualizar display_name, default_currency_id y timezone |

No permite modificar el identificador del usuario.

### 9.5. Validación de precisión monetaria

Los parámetros monetarios de las RPC deben recibirse como `numeric` sin tipificación de escala limitada antes de validar el valor original.

Antes de insertar en `numeric(18,4)`, la función debe comprobar:

- Que el importe no exceda la precisión admitida.
- Que no tenga más decimales que los permitidos por la moneda.
- Que respete los límites del tipo de dato.
- Que el importe sea válido para la operación.

La validación debe ejecutarse antes de que PostgreSQL redondee el valor al almacenarlo.

NestJS debe aplicar también validación decimal de entrada. No utilizar `float` ni `double` para importes financieros.

### 9.6. Seguridad de las RPC

Las funciones no deben aceptar `user_id` como dato confiable.

El usuario se determina mediante `auth.uid()`.

Las funciones deben validar explícitamente la propiedad de cada cuenta, categoría y transacción involucrada.

No utilizar `service_role` para operaciones ordinarias.

### 9.7. Lecturas y resúmenes

Las lecturas agregadas se resuelven en PostgreSQL para evitar transferir y sumar filas en NestJS.

| Objeto | Tipo | Responsabilidad |
|---|---|---|
| account_balances | Vista | Saldo actual por cuenta y crédito disponible de tarjetas |
| get_monthly_summary | Función | Indicadores mensuales por moneda (sección 6.11) |
| get_monthly_account_flows | Función | Entradas y salidas por cuenta en el período |

Reglas:

- Las vistas se crean con `security_invoker = true`, para que apliquen las políticas RLS del usuario que consulta.
- Las funciones de lectura son `SECURITY INVOKER`, `STABLE` y no reciben `user_id`.
- Las funciones de resumen reciben año y mes, y calculan los límites del período con `profiles.timezone`.
- `authenticated` recibe SELECT sobre las vistas y EXECUTE sobre las funciones de lectura; `anon` no recibe acceso.

---

## 10. Concurrencia y bloqueos

Las operaciones financieras deben protegerse frente a solicitudes concurrentes.

### 10.1. Bloqueo de cuentas

Antes de utilizar una cuenta en una operación:

- Bloquear la fila mediante `SELECT ... FOR UPDATE`.
- Comprobar que pertenece al usuario autenticado.
- Comprobar que está activa.
- Comprobar que su moneda coincide con la operación.

Cuando se bloqueen varias cuentas, hacerlo siempre en orden determinístico por UUID.

Esto evita que dos operaciones concurrentes utilicen una cuenta mientras se está modificando o desactivando.

### 10.2. Modificación del saldo inicial

La modificación de `initial_balance` debe bloquear la fila de cuenta.

La creación de movimientos debe bloquear esa misma fila.

Así se garantiza que una modificación del saldo inicial no compita con la creación del primer movimiento.

Una vez que existe al menos un movimiento, el saldo inicial queda inmutable.

### 10.3. Bloqueo de categorías

Las operaciones que utilizan una categoría deben bloquear su fila antes de validar su estado y tipo.

Las operaciones que modifican la jerarquía deben bloquear las categorías involucradas, incluida la categoría padre.

Esto evita carreras entre:

- Desactivación de categorías.
- Creación de operaciones.
- Modificación de subcategorías.
- Eliminación de categorías.

### 10.4. Devoluciones concurrentes

`create_refund` debe:

1. Bloquear el gasto original mediante `SELECT ... FOR UPDATE`.
2. Verificar que pertenece al usuario.
3. Verificar que está `posted`.
4. Consultar las devoluciones `posted` existentes.
5. Calcular el importe pendiente.
6. Rechazar una devolución superior al saldo disponible.
7. Insertar la transacción y su movimiento.

El bloqueo del gasto original serializa las devoluciones concurrentes.

### 10.5. Anulaciones concurrentes

`void_transaction` debe bloquear la transacción objetivo.

Al anular un gasto, debe comprobar nuevamente que no existen devoluciones `posted`.

La creación de una devolución y la anulación del gasto original compiten por el mismo bloqueo, evitando que ambas operaciones se confirmen de forma incompatible.

`void_transaction` y `replace_transaction` también deben bloquear las cuentas afectadas, en orden determinístico por UUID, antes de validar el saldo no negativo de las cuentas líquidas.

### 10.6. Saldo no negativo

Toda operación que reduzca el saldo de una cuenta líquida debe bloquear previamente la fila de la cuenta. Así, dos operaciones concurrentes sobre la misma cuenta se serializan y no pueden dejarla en negativo aunque cada una, por separado, fuera válida.

### 10.7. Idempotencia concurrente

Dos solicitudes simultáneas con el mismo `client_request_id` se resuelven mediante la restricción `UNIQUE (user_id, client_request_id)`: una se confirma y la otra devuelve la transacción existente.

### 10.8. Nivel de aislamiento

Las RPC utilizan el aislamiento normal de PostgreSQL, `READ COMMITTED`, salvo que una operación justifique expresamente otro nivel.

Las invariantes financieras deben garantizarse mediante bloqueos, restricciones y triggers, no mediante suposiciones sobre el orden de llegada de las solicitudes.

---

## 11. Índices

Crear índices para las claves foráneas y consultas frecuentes.

### 11.1. accounts

- Índice por `(user_id, is_active)`.
- Restricción única `(id, user_id, currency_id)`.

### 11.2. categories

- Índice por `(user_id, type, is_active)`.
- Índice por `(parent_id, user_id, type)`.
- Índices únicos parciales para nombres de categorías raíz y subcategorías, utilizando `lower(btrim(name))`.

### 11.3. transactions

- Índice por `(user_id, occurred_at DESC, id DESC)`.
- Índice por `(user_id, type, occurred_at DESC)`.
- Índice por `(user_id, category_id, occurred_at DESC)`.
- Índice por `related_transaction_id`.
- Restricción única `(id, user_id, currency_id)`.
- Restricción única `(id, user_id, type)`.
- Restricción única `(user_id, client_request_id)`.
- Índice único parcial por `replaces_transaction_id` cuando no es NULL.

### 11.4. account_movements

- Índice por `(account_id, occurred_at DESC, id DESC)`.
- Índice por `(user_id, transaction_id)`.
- Índice por `(user_id, account_id, occurred_at DESC)`.
- Restricción única `(transaction_id, account_id)`.

Los índices deben revisarse mediante planes de ejecución cuando existan consultas reales. No agregar índices redundantes sin una necesidad demostrada.

---

## 12. Purga de usuarios

La eliminación de un usuario debe eliminar sus datos financieros de forma controlada.

La relación `profiles.id → auth.users.id` utiliza `ON DELETE CASCADE`.

Un trigger `BEFORE DELETE` sobre `profiles` ejecuta la purga mediante la función `trg_profiles_purge_user_data`.

La función:

- Es `SECURITY DEFINER`.
- Pertenece a `app_user_purger`.
- Utiliza un `search_path` protegido.
- No se expone como RPC.
- Elimina únicamente los datos asociados al usuario cuyo perfil está siendo eliminado.

Orden de eliminación:

1. `account_movements`
2. `transactions` (en una única sentencia)
3. `accounts`
4. `categories` (en una única sentencia)

La eliminación de movimientos antes de las transacciones respeta las claves foráneas.

Las referencias internas (devoluciones, reemplazos y subcategorías) se resuelven eliminando cada tabla en una única sentencia, gracias a que las claves foráneas utilizan `NO ACTION`, que se verifica al final de la sentencia (ver sección 5).

Como `accounts`, `categories` y `transactions` referencian `profiles(id)`, la purga debe completarse en el trigger `BEFORE DELETE` de `profiles`, antes de que se elimine la fila del perfil.

Las políticas RLS específicas permiten al rol purgador ejecutar estas operaciones sin concederle `BYPASSRLS`.

Los triggers de inmutabilidad permiten los DELETE únicamente cuando `current_user = 'app_user_purger'`.

No se utiliza una variable GUC como autorización de purga.

La eliminación del perfil se completa mediante la cascada originada por la eliminación de `auth.users`.

La operación completa debe ser atómica: si falla cualquier etapa, no debe quedar una purga parcial confirmada.

---

## 13. Decisiones técnicas

### 13.1. Migraciones

Utilizar Supabase CLI y migraciones SQL versionadas en Git.

Las migraciones deben poder ejecutarse de manera reproducible en entornos locales y remotos.

No modificar manualmente la estructura de producción fuera del sistema de migraciones.

### 13.2. Lecturas

Las lecturas se realizan desde NestJS mediante el cliente Supabase autenticado con el JWT del usuario.

Las consultas deben respetar RLS.

Los resúmenes y balances se calculan a partir de movimientos y transacciones contabilizadas, mediante los objetos de lectura definidos en la sección 9.7.

### 13.3. Paginación

El historial debe utilizar paginación por cursor, con orden estable:

`(occurred_at DESC, id DESC)`

Evitar depender exclusivamente de `OFFSET` para historiales extensos.

### 13.4. Monedas

Los importes de distintas monedas nunca se suman directamente.

Los balances se presentan separados por moneda.

Las transferencias entre monedas diferentes no están permitidas en V1.

### 13.5. Eliminación de datos

La eliminación de cuentas y categorías utilizadas se sustituye por desactivación.

Las operaciones contabilizadas se anulan, no se eliminan.

La purga de un usuario es la única excepción de eliminación física de los registros financieros y está restringida al mecanismo de purga descrito.

### 13.6. Zona horaria

Las fechas se almacenan en `timestamptz` (instante absoluto). La zona horaria del perfil solo se utiliza para presentar fechas y determinar los períodos de los resúmenes.

Si el usuario cambia su zona horaria, los resúmenes se recalculan con la nueva zona; los datos almacenados no se modifican.

### 13.7. Pruebas de base de datos

Los criterios de aceptación de la sección 15 se automatizan con pgTAP, ejecutado mediante `supabase test db`, incluido en la Supabase CLI del proyecto.

- Las pruebas se ubican en `supabase/tests/database/`.
- Se ejecutan contra la base local o un entorno de pruebas, nunca contra producción.
- Cada prueba simula usuarios autenticados mediante sus claims JWT para verificar RLS y las RPC.

---

## 14. Evolución futura

El modelo debe permitir incorporar posteriormente:

- Cuentas compartidas.
- Grupos familiares.
- Gastos compartidos.
- Cuotas de tarjetas.
- Fechas de cierre y vencimiento.
- Conversión entre monedas.
- Tipos de cambio históricos.
- Reportes avanzados.
- Presupuestos y objetivos financieros.

Estas funcionalidades no deben incorporarse anticipadamente al esquema de V1 si no son necesarias para cumplir los requisitos actuales.

---

## 15. Criterios de aceptación del modelo

El modelo no se considera implementado hasta que las pruebas demuestren:

### Integridad y aislamiento

- Un usuario no puede consultar ni modificar datos de otro.
- No pueden relacionarse cuentas, categorías o transacciones de usuarios diferentes.
- No pueden realizarse operaciones entre monedas distintas.
- Las funciones RPC no aceptan identidades proporcionadas por el cliente.

### Reglas financieras

- Los ingresos incrementan correctamente una cuenta líquida.
- Los gastos reducen correctamente una cuenta líquida o incrementan la deuda de una tarjeta.
- Las transferencias no alteran el total consolidado de una misma moneda.
- Los pagos de tarjeta no generan gastos duplicados.
- Las devoluciones incrementan correctamente el saldo de la cuenta receptora.
- Las devoluciones acumuladas nunca superan el gasto original.
- Los ajustes afectan correctamente el saldo.
- Una cuenta líquida nunca queda con saldo negativo, incluso tras anulaciones o reemplazos.
- Un gasto con tarjeta se registra aunque supere el límite de crédito.
- Los resúmenes excluyen transferencias y ajustes de ingresos y gastos, y los informan por separado.
- Los períodos mensuales respetan la zona horaria del usuario.

### Historial

- Una operación contabilizada no puede modificarse en sus campos financieros.
- Una operación anulada no puede reactivarse.
- Los movimientos históricos permanecen inmutables.
- Las operaciones anuladas dejan de afectar los saldos.
- Un reemplazo anula la original y crea la corregida de forma atómica, conservando el vínculo entre ambas.
- Un reintento con el mismo `client_request_id` no genera duplicados.

### Concurrencia

- Dos devoluciones concurrentes no pueden superar el importe original.
- No puede registrarse una operación en una cuenta que fue desactivada antes de obtener el bloqueo.
- No puede modificarse el saldo inicial después de existir movimientos.
- No puede anularse un gasto mientras existan devoluciones contabilizadas.

### Seguridad

- Los usuarios no pueden ejecutar DML directo sobre las tablas de dominio.
- Las RPC solo permiten las operaciones autorizadas.
- Las funciones privilegiadas tienen permisos mínimos.
- RLS se mantiene activo incluso para los roles de ejecución.
- El rol purgador no puede ser asumido por una sesión autenticada.
- La purga elimina todos los registros dependientes en una única transacción.

### Precisión

- PYG no admite fracciones de guaraní.
- USD no admite más de dos decimales.
- Los importes no se procesan mediante tipos de punto flotante.
- La base de datos rechaza importes con precisión no permitida antes de su almacenamiento.

---

## 16. Historial de cambios

| Versión | Cambios |
|---|---|
| 1.2 | Diseño técnico cerrado. |
| 1.3 | `user_id` referencia `profiles(id)`; FK financieras con `NO ACTION`; purga simplificada; saldo no negativo en cuentas líquidas; límite de crédito informativo; zona horaria del perfil; reglas de resúmenes (transferencias y ajustes por separado); edición mediante reemplazo atómico; idempotencia con `client_request_id`; vistas y funciones de lectura; pruebas con pgTAP; sin categorías predefinidas. |

---

**Fin del documento — DATA_MODEL.md v1.3**