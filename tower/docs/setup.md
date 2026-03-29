# Bootstrap Setup Guide

Complete these steps once before the first `tofu apply`. All steps use the OCI Console unless the OCI CLI is noted.

---

## 1. Create an OCI API Key

1. Log into the OCI Console → **Profile** (top-right) → **My profile**
2. Under **Resources**, click **API keys** → **Add API key**
3. Choose **Generate API key pair**, download both files
4. Copy the **Configuration file preview** — you will need `fingerprint`, `tenancy`, `user`, and `region`

---

## 2. Create a Customer Secret Key (for S3-compatible backend)

1. OCI Console → **Profile** → **My profile** → **Customer secret keys** → **Generate secret key**
2. Name it `infrastructure-state`
3. **Copy the secret immediately** — it is only shown once
4. Note the **Access Key** shown in the list after creation

---

## 3. Create the Object Storage Bucket

1. OCI Console → **Storage** → **Object Storage & Archive Storage** → **Buckets**
2. Select your compartment
3. Click **Create Bucket**
   - Name: `infrastructure-state` (or your preferred name)
   - Storage tier: **Standard**
   - Leave versioning off
4. Find your **Object Storage Namespace**: shown on the Bucket list page under the region selector, or via:
   ```bash
   oci os ns get
   ```

---

## 4. Create a Cloudflare API Token

1. Cloudflare dashboard → **My Profile** → **API Tokens** → **Create Token**
2. Use the **Edit zone DNS** template
3. Under **Zone Resources**, select `sqrd-dns.com`
4. Create the token and copy it — shown only once
5. Note the **Zone ID** for `sqrd-dns.com` from the zone's overview page (right-hand sidebar)

---

## 5. Add GitHub Secrets

Secrets are split between repository-level (shared across all OpenTofu nodes) and environment-level (tower-specific).

### Repository secrets

In your GitHub repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**:

| Secret name | Where to find the value |
|---|---|
| `OCI_S3_REGION` | Region where the state bucket lives (e.g. `eu-frankfurt-1`) |
| `OCI_S3_NAMESPACE` | Object Storage namespace — from Step 3 |
| `OCI_S3_BUCKET` | Bucket name from Step 3 (e.g. `infrastructure-state`) |
| `OCI_S3_ACCESS_KEY` | Access Key from Step 2 |
| `OCI_S3_SECRET_KEY` | Secret from Step 2 (shown only once) |

These are reused by every OpenTofu node in this repo — add them once, not per node. Using an `OCI_S3_` prefix keeps the backend credentials distinct from node-level `OCI_REGION`, allowing nodes in different regions to share the same state bucket.

### Environment secrets (`tower`)

In your GitHub repository → **Settings** → **Environments** → **tower** (create if it doesn't exist) → **Add environment secret**:

| Secret name | Where to find the value |
|---|---|
| `OCI_REGION` | Configuration file preview from Step 1 (`region`, e.g. `eu-frankfurt-1`) |
| `OCI_TENANCY_OCID` | Configuration file preview from Step 1 (`tenancy`) |
| `OCI_USER_OCID` | Configuration file preview from Step 1 (`user`) |
| `OCI_FINGERPRINT` | Configuration file preview from Step 1 (`fingerprint`) |
| `OCI_PRIVATE_KEY` | Full content of the downloaded `.pem` private key file |
| `OCI_COMPARTMENT_OCID` | OCI Console → **Identity** → **Compartments** (use tenancy OCID for root) |
| `SSH_AUTHORIZED_KEYS` | JSON array of SSH public keys, e.g. `["ssh-ed25519 AAAA...", "ssh-ed25519 BBBB..."]` |
| `CLOUDFLARE_API_TOKEN` | API token from Step 4 |
| `CLOUDFLARE_ZONE_ID` | Zone ID for `sqrd-dns.com` from Step 4 |

---

## 6. Verify Backend Connectivity (optional, local)

```bash
cd tower/terraform
tofu init \
  -backend-config="bucket=<OCI_S3_BUCKET>" \
  -backend-config="key=tower/terraform.tfstate" \
  -backend-config="region=<OCI_S3_REGION>" \
  -backend-config="endpoint=https://<OCI_S3_NAMESPACE>.compat.objectstorage.<OCI_S3_REGION>.oraclecloud.com" \
  -backend-config="access_key=<OCI_S3_ACCESS_KEY>" \
  -backend-config="secret_key=<OCI_S3_SECRET_KEY>" \
  -backend-config="skip_region_validation=true" \
  -backend-config="skip_credentials_validation=true" \
  -backend-config="skip_metadata_api_check=true" \
  -backend-config="force_path_style=true"
```

Expected: `OpenTofu has been successfully initialized!`

---

## 7. Protect the Main Branch (Ruleset)

1. GitHub repository → **Settings** → **Rules** → **Rulesets** → **New ruleset** → **New branch ruleset**
2. Configure:
   - **Ruleset name**: `Protect main`
   - **Enforcement status**: Active
3. Under **Target branches** → **Add target** → **Include by pattern** → enter `main`
4. Enable these rules:
   - **Restrict deletions** — prevents deleting `main`
   - **Require a pull request before merging** — uncheck "Require approvals" if you're a solo maintainer (set required approvals to `0`), but leave the rule enabled so direct pushes are blocked
   - **Block force pushes** — prevents rewriting history on `main`
5. Click **Create**

The apply workflow triggers on push to `main`, which still works — merging a PR counts as a push. Direct `git push origin main` will be blocked.

---

## 8. First Apply

Create a branch, open a PR → plan runs automatically.
Merge to `main` → apply runs automatically.

The VM is configured with `prevent_destroy = true` and will never be destroyed by OpenTofu.
