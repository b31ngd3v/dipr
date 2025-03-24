# DIPR

## Local Development Setup

### Prerequisites

- [Node.js](https://nodejs.org/) (v16 or higher)
- [DFINITY Canister SDK (dfx)](https://internetcomputer.org/docs/current/developer-docs/setup/install/)
- [pnpm](https://pnpm.io/installation)

### Clone the Repository

```bash
git clone --recurse-submodules git@github.com:b31ngd3v/DIPR
cd DIPR
```

### Deploy the Contracts

1. Navigate to the contracts directory:

```bash
cd contracts
```

2. Run the setup script:

```bash
./setup.sh
```

3. **Important**: Note the canister IDs generated for:
   - internet_identity
   - ip_registry

### Set Up the Frontend

1. Navigate to the frontend directory:

```bash
cd ../frontend
```

2. Install dependencies:

```bash
pnpm install
```

3. Create a `.env` file based on the example:

```bash
cp .env.example .env
```

4. Edit the `.env` file and update it with the canister IDs noted earlier.

### Run the Application

Start the development server:

```bash
pnpm dev
```

The application should now be running locally and accessible through your browser. 