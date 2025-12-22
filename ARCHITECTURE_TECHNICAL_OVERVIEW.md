# Gastro Kiosk Pro - Technical Architecture Overview
**Version**: 3.0.1-terminal-fix  
**Last Updated**: 2025-12-19  
**Architecture Type**: Microservices with Docker Compose

---

## 🏛️ SYSTEM ARCHITECTURE

### High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     GASTRO KIOSK PRO v3.0                       │
│                   Dockerized Microservices                      │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    KIOSK-SERVER (100.64.0.7)                    │
│                   Ubuntu 24.04 LTS + Docker                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              NGINX (Reverse Proxy + SSL)                 │  │
│  │  - Port 3001: Display Client (React SPA)                 │  │
│  │  - Port 3002: Kiosk Client (React SPA)                   │  │
│  │  - Port 3003: Cashier Admin (React SPA)                  │  │
│  │  - Port 8000: Setup Scripts Server                       │  │
│  └──────────────────────────────────────────────────────────┘  │
│                       ▲          ▲          ▲                   │
│                       │          │          │                   │
│  ┌────────────────────┴──────────┴──────────┴──────────────┐  │
│  │              BACKEND API (Node.js + Express)             │  │
│  │  - Port 3000: REST API + WebSocket (Socket.IO)          │  │
│  │  - 40+ Endpoints: Orders, Products, Payments, Auth      │  │
│  │  - Prisma ORM for database abstraction                  │  │
│  └──────────────────────────────────────────────────────────┘  │
│         │                    │                    │              │
│         ▼                    ▼                    ▼              │
│  ┌──────────┐      ┌──────────────┐      ┌──────────────┐     │
│  │PostgreSQL│      │    Redis     │      │Device Manager│     │
│  │   v16    │      │     v7       │      │  (Node.js)   │     │
│  │  :5432   │      │   :6379      │      │   :8090      │     │
│  └──────────┘      └──────────────┘      └──────────────┘     │
│       │                   │                      │              │
│  [Persistent]        [Persistent]           [Heartbeat]        │
│   Volume             Volume                  Registry          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                                │
                    ┌───────────┴───────────┐
                    │   Tailscale VPN       │
                    │   (100.64.0.0/10)     │
                    └───────────┬───────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐      ┌───────────────┐      ┌───────────────┐
│  admin1-rb102 │      │     kiosk     │      │     kiosk2    │
│  (100.64.0.6) │      │  (100.64.0.3) │      │  (100.64.0.2) │
│192.168.31.205 │      │ 192.168.31.35 │      │192.168.31.170 │
├───────────────┤      ├───────────────┤      ├───────────────┤
│ Chromium      │      │ Chromium      │      │ Chromium      │
│ → :3003       │      │ → :3002       │      │ → :3001       │
│ (Cashier)     │      │ (Kiosk)       │      │ (Display)     │
│               │      │               │      │               │
│ Terminal Svc  │      │               │      │               │
│ → :8082 ✅    │      │               │      │               │
│               │      │               │      │               │
│ Printer Svc   │      │               │      │               │
│ → :8081       │      │               │      │               │
└───────────────┘      └───────────────┘      └───────────────┘
```

---

## 📦 CONTAINER ARCHITECTURE

### Container Dependency Graph

```
gastro_postgres ─────┐
                     ├──> gastro_backend ────> gastro_nginx
gastro_redis ────────┘              │
                                    └──> gastro_device_manager
```

### Container Details

#### 1. gastro_postgres
- **Image**: postgres:16-alpine
- **Purpose**: Primary data store
- **Exposed Port**: 127.0.0.1:5432:5432 (localhost only)
- **Volume**: `./postgres-data:/var/lib/postgresql/data`
- **Environment**:
  - `POSTGRES_DB=gastro_kiosk`
  - `POSTGRES_USER=gastro_user`
  - `POSTGRES_PASSWORD=gastro_pass_2024`
- **Health Check**: `pg_isready -U gastro_user -d gastro_kiosk`
- **Restart Policy**: always
- **Status**: ✅ Healthy

#### 2. gastro_redis
- **Image**: redis:7-alpine
- **Purpose**: Session store, caching, real-time data
- **Exposed Port**: 127.0.0.1:6379:6379 (localhost only)
- **Volume**: `./redis-data:/data`
- **Command**: `redis-server --appendonly yes`
- **Health Check**: `redis-cli ping`
- **Restart Policy**: always
- **Status**: ✅ Healthy

#### 3. gastro_backend
- **Image**: Custom build (Node.js 18.20.8)
- **Build Context**: `./backend`
- **Purpose**: REST API + WebSocket server
- **Exposed Port**: 0.0.0.0:3000:3000 (public)
- **Volumes**:
  - `./backend:/app` (code)
  - `./logs/backend:/app/logs` (logs)
- **Environment**:
  - `NODE_ENV=production`
  - `DATABASE_URL=postgresql://gastro_user:***@postgres:5432/gastro_kiosk`
  - `REDIS_URL=redis://redis:6379`
  - `PAYMENT_TERMINAL_URL=http://100.64.0.6:8082`
  - `PRINTER_SERVICE_URL=http://100.64.0.6:8081`
  - `CORS_ORIGINS=http://100.64.0.7:3001,...`
- **Dependencies**: postgres, redis
- **Restart Policy**: always
- **Status**: ⚠️ Unhealthy (but functional)

#### 4. gastro_device_manager
- **Image**: Custom build (Node.js 18)
- **Build Context**: `./device-manager`
- **Purpose**: Device heartbeat tracking and registration
- **Exposed Port**: 0.0.0.0:8090:8090 (public)
- **Volumes**:
  - `./device-manager:/app` (code)
  - `./logs/device-manager:/app/logs` (logs)
- **Environment**:
  - `NODE_ENV=production`
  - `PORT=8090`
- **Dependencies**: postgres
- **Restart Policy**: always
- **Status**: ⚠️ Unhealthy (but functional)

#### 5. gastro_nginx
- **Image**: nginx:alpine
- **Purpose**: Reverse proxy, SSL termination, static file serving
- **Exposed Ports**:
  - 80:80 (HTTP)
  - 443:443 (HTTPS)
  - 3001:3001 (Display - HTTPS)
  - 3002:3002 (Kiosk - HTTPS)
  - 3003:3003 (Cashier - HTTPS)
  - 8000:8000 (Setup scripts - HTTP)
- **Volumes**:
  - `./nginx/nginx.conf:/etc/nginx/nginx.conf:ro`
  - `./nginx/conf.d:/etc/nginx/conf.d:ro`
  - `./nginx/ssl:/etc/nginx/ssl:ro`
  - `./frontends:/usr/share/nginx/html:ro`
  - `./setup-scripts:/usr/share/nginx/html/setup:ro`
  - `./logs/nginx:/var/log/nginx`
- **Dependencies**: backend
- **Restart Policy**: always
- **Status**: ✅ Running

---

## 🗄️ DATABASE SCHEMA

### Tables (10 entities)

```sql
┌──────────────────────┐     ┌──────────────────────┐
│       users          │     │     categories       │
├──────────────────────┤     ├──────────────────────┤
│ id (PK)              │     │ id (PK)              │
│ username             │     │ name                 │
│ password (hashed)    │     │ slug                 │
│ role (ENUM)          │     │ description          │
│ name                 │     │ displayOrder         │
│ email                │     │ active               │
│ active               │     │ image                │
│ createdAt            │     │ translations (JSON)  │
│ updatedAt            │     └──────────────────────┘
└──────────────────────┘              │
                                      │ 1:N
                                      ▼
┌──────────────────────┐     ┌──────────────────────┐
│      modifiers       │◄─┐  │      products        │
├──────────────────────┤  │  ├──────────────────────┤
│ id (PK)              │  │  │ id (PK)              │
│ name                 │  │  │ name                 │
│ type (ENUM)          │  └──│ categoryId (FK)      │
│ options (JSON)       │     │ slug                 │
│ productId (FK)       │     │ description          │
└──────────────────────┘     │ price                │
                             │ image                │
                             │ active               │
                             │ prepTime             │
                             │ translations (JSON)  │
                             └──────────────────────┘
                                      │
                                      │ N:1
                                      ▼
┌──────────────────────┐     ┌──────────────────────┐
│    order_items       │     │       orders         │
├──────────────────────┤     ├──────────────────────┤
│ id (PK)              │     │ id (PK)              │
│ orderId (FK)         │◄────│ orderNumber          │
│ productId (FK)       │     │ userId (FK)          │
│ quantity             │     │ status (ENUM)        │
│ price                │     │ paymentMethod        │
│ modifiers (JSON)     │     │ paymentStatus        │
└──────────────────────┘     │ totalAmount          │
                             │ notes                │
                             │ completedAt          │
                             │ createdAt            │
┌──────────────────────┐     │ updatedAt            │
│order_status_history  │     └──────────────────────┘
├──────────────────────┤              │
│ id (PK)              │              │ 1:1
│ orderId (FK)         │◄─────────────┤
│ status (ENUM)        │              │
│ userId (FK)          │              ▼
│ timestamp            │     ┌──────────────────────┐
└──────────────────────┘     │payment_transactions  │
                             ├──────────────────────┤
┌──────────────────────┐     │ id (PK)              │
│      settings        │     │ orderId (FK) UNIQUE  │
├──────────────────────┤     │ transactionId        │
│ id (PK)              │     │ amount               │
│ key (UNIQUE)         │     │ status (ENUM)        │
│ value                │     │ paymentMethod        │
│ type                 │     │ authCode             │
│ description          │     │ cardNumber           │
│ updatedAt            │     │ stan                 │
└──────────────────────┘     │ errorCode            │
                             │ errorMessage         │
┌──────────────────────┐     │ createdAt            │
│     audit_logs       │     │ updatedAt            │
├──────────────────────┤     └──────────────────────┘
│ id (PK)              │
│ userId (FK)          │
│ action               │
│ entityType           │
│ entityId             │
│ changes (JSON)       │
│ ipAddress            │
│ timestamp            │
└──────────────────────┘
```

### Key Relationships

- **User → Order**: One-to-many (user can place multiple orders)
- **Category → Product**: One-to-many (category contains multiple products)
- **Product → Modifier**: One-to-many (product can have multiple modifiers)
- **Order → OrderItem**: One-to-many (order contains multiple items)
- **OrderItem → Product**: Many-to-one (item references a product)
- **Order → PaymentTransaction**: One-to-one (order has one payment)
- **Order → OrderStatusHistory**: One-to-many (order status changes tracked)

---

## 🔌 API ARCHITECTURE

### REST API Endpoints (40+ endpoints)

#### Authentication
- `POST /api/auth/login` - User login (JWT)
- `POST /api/auth/logout` - User logout
- `GET /api/auth/me` - Current user info

#### Categories
- `GET /api/categories` - List all categories
- `GET /api/categories/:id` - Get category by ID
- `POST /api/categories` - Create category (admin)
- `PUT /api/categories/:id` - Update category (admin)
- `DELETE /api/categories/:id` - Delete category (admin)

#### Products
- `GET /api/products` - List products (filter by categoryId)
- `GET /api/products/:id` - Get product by ID
- `POST /api/products` - Create product (admin)
- `PUT /api/products/:id` - Update product (admin)
- `DELETE /api/products/:id` - Delete product (admin)

#### Orders
- `GET /api/orders` - List orders (filter by status)
- `GET /api/orders/:id` - Get order by ID
- `POST /api/orders` - Create order
- `PUT /api/orders/:id/status` - Update order status
- `DELETE /api/orders/:id` - Cancel order

#### Payment
- `POST /api/payment/initiate` - Start payment transaction
- `POST /api/payment/callback` - Terminal callback (webhook)
- `GET /api/payment/:transactionId` - Get payment status

#### Users (Admin)
- `GET /api/users` - List users
- `POST /api/users` - Create user
- `PUT /api/users/:id` - Update user
- `DELETE /api/users/:id` - Delete user

#### Health & Status
- `GET /health` - Health check
- `GET /api/stats` - Dashboard statistics (admin)

### WebSocket Events (Socket.IO)

#### Client → Server
- `connection` - Client connects
- `disconnect` - Client disconnects
- `join:device` - Device joins room (deviceId)

#### Server → Client
- `order:created` - New order created
- `order:updated` - Order status changed
- `payment:initiated` - Payment started
- `payment:progress` - Payment in progress (card reading, authorizing)
- `payment:completed` - Payment successful
- `payment:failed` - Payment failed (error details)
- `payment:cancelled` - Payment cancelled by user

---

## 🖥️ FRONTEND ARCHITECTURE

### Technology Stack
- **Framework**: React 18
- **Language**: TypeScript
- **Build Tool**: Vite
- **State Management**: React Context + Hooks
- **Styling**: TailwindCSS
- **Icons**: Lucide React
- **i18n**: react-i18next (PL/EN/DE/UA)
- **WebSocket**: Socket.IO Client

### Three Frontend Applications

#### 1. Kiosk Client (Port 3002)
**Purpose**: Customer self-service ordering interface

**Key Features**:
- Product browsing by category
- Shopping cart management
- Modifier selection (size, extras, sauce)
- Dual payment methods: Cash / Card
- Smart device detection (hides card payment if terminal offline)
- Multi-language support (4 languages)
- Touch-optimized UI (large buttons, clear typography)
- Payment terminal modal with real-time status
- Order confirmation with receipt display

**Key Components**:
- `HomePage.tsx` - Welcome screen
- `MenuPage.tsx` - Product catalog
- `CheckoutPage.tsx` - Payment selection
- `PaymentTerminalModal.tsx` - Card payment flow
- `ConfirmationPage.tsx` - Order success

**Custom Hooks**:
- `useDeviceCapabilities.ts` - Detects printer/terminal availability
- `useCart.ts` - Cart state management
- `useWebSocket.ts` - Real-time order updates

#### 2. Cashier Admin (Port 3003)
**Purpose**: Kitchen/cashier order management interface

**Key Features**:
- Kanban board with order workflow
- Order status management (drag-and-drop)
- Product/category CRUD operations
- User management (admin only)
- Dashboard with statistics
- Order search and filtering
- Print receipt functionality
- Real-time order updates (WebSocket)

**Order Statuses**:
- `PENDING` - New order (payment pending)
- `IN_PROGRESS` - Being prepared
- `READY` - Ready for pickup
- `COMPLETED` - Delivered
- `CANCELLED` - Cancelled

**Key Components**:
- `Dashboard.tsx` - Statistics overview
- `OrderBoard.tsx` - Kanban board
- `ProductManagement.tsx` - Product CRUD
- `CategoryManagement.tsx` - Category CRUD
- `UserManagement.tsx` - User CRUD

#### 3. Display Client (Port 3001)
**Purpose**: Customer-facing order number display

**Key Features**:
- Large order numbers (highly visible)
- Shows orders: IN_PROGRESS + READY
- Auto-cycling languages (10s intervals)
- Color-coded status (yellow/green)
- Automatic updates via WebSocket
- Minimal UI (optimized for readability)

**Key Components**:
- `DisplayPage.tsx` - Main display screen

---

## 🔐 SECURITY ARCHITECTURE

### Authentication & Authorization
- **Method**: JWT (JSON Web Tokens)
- **Storage**: HTTP-only cookies (planned) / localStorage (current)
- **Roles**: ADMIN, CASHIER, VIEWER
- **Password Hashing**: bcrypt (salt rounds: 10)

### Network Security
- **CORS**: Configured for specific origins (Tailscale IPs)
- **SSL/TLS**: Self-signed certificates (Nginx)
- **Database**: Localhost-only binding (127.0.0.1)
- **Redis**: Localhost-only binding (127.0.0.1)
- **VPN**: Tailscale for inter-device communication

### API Security
- **Rate Limiting**: Planned (not yet implemented)
- **Input Validation**: Prisma schema validation
- **SQL Injection**: Protected by Prisma ORM
- **XSS**: React escaping by default

---

## 🔄 DATA FLOW

### Order Creation Flow

```
Customer (Kiosk) → Backend → Database → WebSocket → Cashier/Display
     │                 │          │          │              │
     │ POST /orders    │          │          │              │
     ├─────────────────>│          │          │              │
     │                 │ INSERT   │          │              │
     │                 ├──────────>│          │              │
     │                 │          │ COMMIT   │              │
     │                 │          ├──────────>│              │
     │                 │          │          │ emit:created │
     │                 │          │          ├──────────────>│
     │ 201 Created     │          │          │              │
     │<────────────────┤          │          │              │
     │                 │          │          │              │
```

### Payment Flow

```
Kiosk → Backend → Terminal Service → Ingenico Terminal
  │        │            │                    │
  │ POST /payment/initiate                   │
  ├────────>│            │                    │
  │        │ POST /payment/start              │
  │        ├────────────>│                    │
  │        │            │ UDP: UP00101       │
  │        │            ├────────────────────>│
  │        │            │                    │ [User taps card]
  │        │            │ UDP: UP10152 (progress)
  │        │            │<────────────────────┤
  │        │ POST /callback (progress)       │
  │        │<───────────┤                    │
  │ WS: payment:progress                     │
  │<───────┤            │                    │
  │        │            │ UDP: UP10151 (result)
  │        │            │<────────────────────┤
  │        │ POST /callback (result)         │
  │        │<───────────┤                    │
  │        │ UPDATE payment_transactions     │
  │        │            │                    │
  │ WS: payment:completed                    │
  │<───────┤            │                    │
```

---

## 📊 MONITORING & LOGGING

### Container Logs
- **Backend**: `/logs/backend/app.log`
- **Device Manager**: `/logs/device-manager/service.log`
- **Nginx Access**: `/logs/nginx/access.log`
- **Nginx Error**: `/logs/nginx/error.log`

### Health Checks
- **Backend**: `GET http://localhost:3000/health`
- **Device Manager**: `GET http://localhost:8090/health`
- **PostgreSQL**: `pg_isready` (internal)
- **Redis**: `redis-cli ping` (internal)

### Metrics (Planned)
- Request rate
- Response time
- Error rate
- Database query performance
- Order processing time

---

## 🚀 DEPLOYMENT WORKFLOW

### Development → Production

```
1. CODE CHANGE
   ├─ Backend: Edit files in ~/gastro-kiosk-backend/
   ├─ Frontend: Edit files in ~/kiosk-client-frontend/
   └─ Device Manager: Edit files in ~/gastro-kiosk-docker/device-manager/

2. BUILD
   ├─ Backend: Copy to docker/backend/, rebuild container
   ├─ Frontend: npm run build, copy dist/ to docker/frontends/
   └─ Device Manager: Edit in place, rebuild container

3. DEPLOY
   ├─ Docker: docker compose up -d --build [service]
   └─ Nginx: Automatic (serves updated static files)

4. VERIFY
   ├─ docker compose ps
   ├─ docker compose logs [service]
   └─ curl health endpoints
```

## SERVICE LOCATIONS & PORTS (Kiosk Server)
| Service | Port | Source Code Path | Docker Volume / Deployment Path |
| :--- | :--- | :--- | :--- |
| **Kiosk (Customer)** | `3002` | `~/kiosk-client-frontend/` | `~/gastro-kiosk-docker/frontends/kiosk/` |
| **Cashier (Kitchen)** | `3003` | `~/cashier-admin-frontend/` | `~/gastro-kiosk-docker/frontends/cashier/` |
| **Display (Status)** | `3001` | `~/display-client/` | `~/gastro-kiosk-docker/frontends/display/` |
| **Backend API** | `3000` | `~/gastro-kiosk-backend/` | *(Docker Container Build)* |
| **Printer Service** | `8081` | `/opt/gastro-printer-service/` | *(Systemd Service)* |
| **Terminal Service** | `8082` | `~/payment-terminal-service/` | *(Systemd Service)* |
> [!NOTE]
> `~` represents the home directory of the kiosk user (e.g., `/home/kiosk-server`).
---
## 🚀 DEPLOYMENT WORKFLOW
### 1. Frontends (Kiosk, Cashier, Display)
Docker serves frontend files from `~/gastro-kiosk-docker/frontends/...`. Changes in source code **must be built and copied** to these folders.
1.  **Edit Code**: Navigate to the source folder (e.g., `~/cashier-admin-frontend/`).
2.  **Build**: Run the build command.
    ```bash
    npm run build
    ```
3.  **Deploy**: Copy the built artifacts to the Docker volume folder.
    ```bash
    # Example for Cashier
    cp -r dist/* ~/gastro-kiosk-docker/frontends/cashier/
    
    # Example for Kiosk
    cp -r dist/* ~/gastro-kiosk-docker/frontends/kiosk/
    
    # Example for Display
    cp -r dist/* ~/gastro-kiosk-docker/frontends/display/
    ```
4.  **Verify**: Refresh the browser (Ctrl+F5). No Docker restart required (Nginx serves static files).
### 2. Backend (Node.js API)
1.  **Edit Code**: Modify files in `~/gastro-kiosk-backend/`.
2.  **Build & Restart**:
    ```bash
    cd ~/gastro-kiosk-docker/
    docker compose up -d --build backend
    ```
3.  **Verify**:
    ```bash
    docker compose logs -f backend
    ```
### 3. Services (Printer & Terminal)
These are systemd services, not Docker containers.
1.  **Edit Code**:
    -   Printer: `/opt/gastro-printer-service/`
    -   Terminal: `~/payment-terminal-service/`
2.  **Restart Service**:
    ```bash
    # Printer
    sudo systemctl restart gastro-printer.service
    
    # Terminal
    sudo systemctl restart payment-terminal.service
    ```

### Rollback Procedure

```
1. STOP DOCKER SERVICES
   docker compose down

2. RESTORE FROM BACKUP
   gunzip -c backup.sql.gz | docker exec -i gastro_postgres psql -U gastro_user -d gastro_kiosk

3. REVERT CODE
   git checkout [previous-commit]
   docker compose up -d --build

4. VERIFY
   Check health endpoints
```

---

## 🔧 MAINTENANCE TASKS

### Daily
- [ ] Check container status: `docker compose ps`
- [ ] Review error logs: `docker compose logs --tail 50`
- [ ] Monitor disk space: `df -h`

### Weekly
- [ ] Database backup: `docker exec gastro_postgres pg_dump`
- [ ] Check device heartbeats: `curl http://localhost:8090/devices`
- [ ] Review order statistics

### Monthly
- [ ] Update Docker images: `docker compose pull`
- [ ] Clean unused images: `docker system prune -a`
- [ ] Review and rotate logs
- [ ] Security updates: `apt update && apt upgrade`

---

## 📞 TROUBLESHOOTING QUICK REFERENCE

### Container Won't Start
```bash
docker compose logs [service]
docker inspect [container]
docker compose up [service]  # Interactive mode
```

### Database Connection Issues
```bash
docker exec -it gastro_postgres psql -U gastro_user -d gastro_kiosk
# Check DATABASE_URL in backend .env
```

### Frontend Not Loading
```bash
# Check Nginx logs
docker compose logs nginx
# Verify static files exist
ls -la /home/kiosk-server/gastro-kiosk-docker/frontends/kiosk/
```

### Payment Terminal Not Responding
```bash
# Check device is online
curl http://100.64.0.6:8082/health
# Check Tailscale connectivity
tailscale status
```

---

**Document Version**: 1.0  
**Last Review**: 2025-12-16  
**Next Review**: 2025-12-30
