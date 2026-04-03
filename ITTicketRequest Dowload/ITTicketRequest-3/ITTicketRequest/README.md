# ITTicketRequest — Bernina Thailand IT Ticket System

IT Access Right Request System with new approval workflow.

## Tech Stack
- ASP.NET Core 8 MVC | Bootstrap 5.3 | SQL Server (BTITReq DB) | BT SSO

## Approval Flow
```
Requester → Dept Manager (8)
               │
               ├─ VPN? Yes → Managing Director (4) ──┐
               │                                      │
               └─ VPN? No  ─────────────────────────→ IT Manager (7)
                                                       │
                                                  IT Admin Assign PIC (5)
                                                       │
                                                  IT Person Incharge (6)
                                                       │
                                                  IT Admin Close Ticket (9)
                                                       │
                                                     End
```

## Status Values (DB)
| Status | Description |
|--------|-------------|
| PendingDeptMgr | Awaiting Dept Manager |
| PendingManagingDir | Awaiting Managing Director (VPN only) |
| PendingITMgr | Awaiting IT Manager |
| PendingITAdminAssign | IT Admin selects IT PIC |
| PendingITPIC | IT PIC working on ticket |
| PendingITAdminClose | IT Admin closes ticket |
| Completed | Done |
| Rejected | Rejected |

## FUNCODE Mapping (TBUserFunction)
| FUNCODE | Role |
|---------|------|
| 4 | Managing Director |
| 5 | IT Admin / Staff |
| 6 | IT Person Incharge (IT PIC) |
| 7 | IT Manager |
| 8 | Department Manager |
| 9 | System Admin |

## Setup
1. Run SQL scripts in order: `SQL/01` → `SQL/04`
2. Configure `appsettings.json` (AuthenUrl, DB, URLSITE)
3. Build: `dotnet publish -c Release -o ./publish`

## Document Format
`TKT-YYYY-NNNN` (e.g. TKT-2026-0001)
