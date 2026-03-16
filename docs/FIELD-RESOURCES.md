# Field Resources — Vault Agentic IAM Demo

> This section is copied verbatim from the original HashiCorp demo README to
> provide field teams with all the context needed to present and deliver this demo.

---

## The Pain

The Confused Deputy problem occurs when a service with high privileges performs actions on behalf of another user or system without properly enforcing identity boundaries. In distributed environments—especially when multiple clouds and identity providers are involved—this creates significant risk: a single service could unintentionally access or modify data it should never touch. This demo replicates that exact scenario and then demonstrates how it can be completely mitigated using HashiCorp Vault as the central authority for secrets, policies, and identity mapping.

---

## The Solution

The Confused Deputy problem is fundamentally a question of trust: how do we ensure that every system acts only within the boundaries of the user it represents? This demo demonstrates how HashiCorp Vault provides that answer by becoming the policy-driven source of truth for identity and authorization across clouds. Vault solves the problem by introducing dynamic, identity-aware security, where permissions are no longer static or implicit—they're evaluated in real time, scoped by policy, and backed by verifiable identity. Through the On-Behalf-Of (OBO) token flow, user identity is securely propagated across every layer of the application. Each service acts only on behalf of a validated user, never under blanket system privileges. Here's how it works in practice:

- A user authenticates through Microsoft Entra ID, obtaining a signed JWT.
- The Agent API exchanges this for an OBO token, representing delegated user identity for backend operations.
- The MCP server presents that delegated token to Vault, which verifies it, maps the user's group claims to policies, and issues short-lived credentials (for example, database access like MongoDB).
- Every issued secret expires automatically and can be revoked at any time, closing the loop on privilege misuse.

Vault acts as the trust orchestrator:

- It enforces least privilege, ensuring that no service ever exceeds the permissions of the user it represents.
- It delivers dynamic, auditable credentials—no more static keys or hard-coded tokens.
- It turns authentication events into fine-grained authorization decisions, consistent across AWS, Entra ID, and Terraform Cloud.
- In short, Vault transforms the traditional "trust by configuration" model into trust by verification.
- It provides a live demonstration of how organizations can eliminate the Confused Deputy pattern, ensuring every service, every action, and every credential is authenticated, authorized, and accounted for.

---

## Demo Recording

[Here](https://drive.google.com/file/d/1WpbQ3ArA3JP3gz5Rs96jXY29HOUQJVNC/view?usp=sharing) is a "golden" recording of this demo - meaning it is the recommended workflow for running this demo. Additionally, [here](https://drive.google.com/file/d/1QfWIGRnEM_b0RimVtSE4cBLWsUKFsJJ3/view?usp=sharing) is a "golden" recording walking users through the Vault On-Behalf-Of (OBO) identity flow. Please use this as a *reference point* for how you run the demo. **This video is NOT meant to be used in lieu of a live demo.**

---

## Slide Deck

[Agentic IAM with Vault second call deck](https://docs.google.com/presentation/d/1Oq-xhAyBq9mFfVaPgPhR9iabJNPLobAthSZnoWwF8IE/edit?slide=id.g3795f4061c1_0_3#slide=id.g3795f4061c1_0_3)

---

## Talk Track and Instructions

### 1. Introduction

**Talk Track:** "Welcome everyone. Today we will walk through the Vault On-Behalf-Of (OBO) identity flow and how it fully eliminates the Confused Deputy problem. This demo shows how user identity travels from Microsoft Entra ID → our application → the Agent API → Vault → and finally to the database through short-lived credentials. You will see how Alice, a read-only user, and Bob, an admin user, receive different permissions automatically, with no hard-coded logic in the application."

**Action:** Show the architecture diagram
- Use the diagram in [docs/ARCHITECTURE.md](./ARCHITECTURE.md) to illustrate the flow.

---

### 2. Architecture Overview

**Talk Track:** "Let's break down the identity flow. When a user logs in through Microsoft Entra ID, the application receives an ID token signed by Entra. This token is sent to the Agent API, which performs an OBO token exchange. The OBO token represents the delegated identity of the user. The Agent API then presents that delegated token to Vault. Vault verifies the signature, extracts group memberships, maps them to Vault policies, and issues short-lived, scoped credentials that the application uses to access MongoDB."

**Action:** Walk through each step visually
- Show Entra ID issuing the JWT.
- Show the Agent API exchanging the token.
- Show Vault issuing dynamic secrets.
- Show MongoDB being accessed with per-user permissions.

---

### 3. Why This Matters: The Confused Deputy Problem

**Talk Track:** "A Confused Deputy happens when a highly privileged service accidentally performs an action on behalf of a user without correct identity boundaries. This demo demonstrates exactly how Vault prevents that: every action is performed strictly within the permissions of the authenticated user, not the permissions of the system. Without Vault, the application would act with its own blanket privileges—leading to privilege escalation. With Vault, the system never exceeds the user's authorization."

---

### 4. Demo Setup: Testing With Alice (Read-Only)

**Talk Track:** "We'll begin with Alice. Alice belongs to the read-only group in Entra ID. That membership is encoded in her token and mapped to read-only policies in Vault. So even though she interacts with the same application UI, all backend permissions come from Vault."

**Action: Sign in as Alice**
- Open the application URL in an incognito window: http://localhost:8501
- Sign in using Alice's credentials (from `terraform output` or your `.env` file).
- Complete MFA if prompted.

**Action: Test read operations**
- Type: **List all products** in the chat interface.
  - If you don't see any products the first time, run the command again.
  - If you don't see the chat section, scroll down to find it.
- Confirm that products appear.

**Action: Attempt a write**
- Type: **Add a new product named "Chair Model X" with price $49.99**
- The request will fail—Vault enforces read-only access.

**Talk Track:** "As you can see, Alice can read products but cannot add new ones. Vault enforced her read-only policy based on her group membership in Entra ID."

---

### 5. Demo Setup: Testing With Bob (Admin)

**Talk Track:** "Next, we will authenticate as Bob. Bob belongs to the admin group in Entra ID. Vault automatically issues policies that allow him to read, write, update, and delete products. The application contains no role logic; it acts only with credentials issued for Bob."

**Action: Sign in as Bob**
- Open a new incognito window using the same app URL: http://localhost:8501
- Sign in with Bob's credentials.
- Complete MFA if required.

**Action: Test read operations**
- Type: **List all products** in the chat interface.
  - If you don't see any products the first time, run the command again.
- Confirm that products appear.

**Action: Test write operations**
- Type: **Add a new product named "Table Model Y" with price $89.99**
- The operation succeeds—Vault issued write permissions.

**Talk Track:** "Bob can both read and add products. Vault enforced his admin-level permissions based on his group membership."

---

### 6. Policy Mapping in Vault

**Talk Track:** "Both users go through the same authentication workflow. The difference is entirely in Vault's policy mapping. Vault validates the OBO token, extracts the 'groups' claims, and applies the appropriate policy. Alice receives read-only MongoDB credentials; Bob receives admin-level credentials. These credentials are short-lived and automatically rotated."

---

### 7. Eliminating the Confused Deputy End-to-End

**Talk Track:** "In this architecture, the application never has long-lived credentials, never holds elevated privileges, and never decides authorization itself. Every operation is performed with credentials tied to the identity of the active user. This ensures that no matter how the application is accessed, it can never perform an action that exceeds the user's permissions."

---

### 8. Conclusion

**Talk Track:** "This demo illustrated how Vault serves as the identity and authorization authority across clouds, enforcing least privilege through real-time policies and short-lived credentials. With this pattern, applications no longer need embedded secrets, static roles, or implicit trust—every action is authenticated, authorized, and fully auditable."
