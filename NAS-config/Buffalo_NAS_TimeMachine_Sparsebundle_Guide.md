# Comprehensive Guide: Reliable Time Machine Backups on Buffalo NAS
## Using Secure `.sparsebundle` Containers Over Hidden SMB Shares

This document details how to configure a network-resilient Time Machine backup architecture using an existing **Buffalo Terastation TS3410D** (or generic SMB NAS). This method bypasses obsolete AFP protocols by wrapping native Mac backups inside an APFS-formatted virtual disk array (`.sparsebundle`), keeping your environment secure, bounded, and fully compatible with **macOS Migration Assistant**.

---

## Part 1: Setting Up the Hidden SMB Share on Buffalo NAS

Hiding your backup target share prevents it from broadcasting to unauthenticated devices on your local network.

1. Log into your **Buffalo TS3410D Web Admin Dashboard**.
2. Navigate to **Advanced Settings** > **File Sharing** > **Folder Setup**.
3. Click **Create Folder** and configure the properties:
   * **Folder Name:** `MacBackup`
   * **Shared Folder Support:** Check **SMB** only.
   * **Hidden Share (SMB Only):** Check **Enable**. 
4. Navigate to **Users/Groups** > **Users** and click **Create User**:
   * **Username:** `tm_user`
   * **Volume Quota:** Check **Enable** and set a strict limit (e.g., `6000 GB` / 6 TB) to prevent the backup container from consuming the entire 12 TB RAID5 array.
5. Return to the `MacBackup` folder properties and restrict **Access Restrictions** so that *only* your new `tm_user` has Read/Write permissions.

---

## Part 2: Mounting the Hidden Share and Creating the Container

Because the share is hidden, it will not appear in the network browser. You must map it manually via its absolute network path.

### 1. Manual Path Mapping
1. Open **Finder** on your Mac and press **Cmd + K** (Connect to Server).
2. Input the explicit path using a trailing dollar sign (`$`) to target the hidden directory:
   ```text
   smb://[IP_OR_HOSTNAME_OF_NAS]/MacBackup$
   ```
   *Example:* `smb://192.168.1.50/MacBackup$`
3. Click **Connect** and authenticate using the credentials for `tm_user`.

### 2. Creating the Rigid Sparsebundle
1. Open **Disk Utility** (`/Applications/Utilities/Disk Utility`).
2. In the top application menu bar, select **File** > **New Image** > **Blank Image...**
3. Configure the parameters exactly as follows:
   * **Save As:** `MyTimeMachine`
   * **Where:** Navigate to and select the mounted `MacBackup$` network folder.
   * **Name:** `Time Machine`
   * **Size:** Define your rigid allocation ceiling (e.g., `500GB`). This acts as the macOS-side quota barrier.
   * **Format:** **APFS**
   * **Partitions:** Single partition - GUID Partition Map
   * **Image Format:** **sparsebundle disk image**
4. Click **Save**. Disk Utility will instantiate the file layout on your NAS and mount a virtual drive volume named `Time Machine` to your desktop.

*Note: If you created the sparsebundle locally on your Mac's internal drive and then manually copied the file to your Buffalo NAS SMB share, proceed directly to Part 3 (Method B) for the required command-line bypass step.*

---

## Part 3: Initiating Native Time Machine Tracking

### Method A: Using System Settings (Natively Created Network Bundles)
If you built the sparsebundle while actively connected to the NAS from the start:
1. Open **System Settings** > **General** > **Time Machine**.
2. Click **Add Backup Disk...**
3. Select the mounted virtual volume named **Time Machine** (marked with a local drive disk icon, *not* a network drive icon).

### Method B: Using Terminal (For Locally Copied / Foreign Bundles)
If you created the `.sparsebundle` on your local Mac hard drive and copied it over to the NAS afterwards, the System Settings GUI will throw a *"No available Time Machine Destinations"* error because it marks it as untrusted. You must force-assign it via the command line:
1. Ensure your hidden NAS folder is mounted and your `.sparsebundle` file inside it is double-clicked and actively open on your desktop.
2. Open **Terminal** (`/Applications/Utilities/Terminal`).
3. Type the following command exactly as structured (using a backslash to escape the space in the volume name):
   ```bash
   sudo tmutil setdestination /Volumes/Time\\ Machine
   ```
4. Press **Enter**, type your Mac's administrator password, and press **Enter** again. 

⚠️ **CRITICAL NOTE ON MULTI-DRIVE ROTATIONS:** The `tmutil setdestination` command operates by replacing your active backup target. Executing this step will temporarily overwrite any existing local physical backup drives you have mapped in your Time Machine interface. 

To restore your multi-drive rotation configuration immediately after running the Terminal command:
1. Navigate to **System Settings** > **General** > **Time Machine**.
2. Verify that your new virtual network container is now recognized and active.
3. Click the **+ (Plus)** or **Add Backup Disk...** button in the graphical user interface.
4. Re-select your physically attached external hard drive from the menu list.
5. macOS will seamlessly establish a native **Backup Rotation pool**, alternating your hourly historical snapshots between the local physical drive and the hidden network sparsebundle sequentially whenever both are available.

---

## Part 4: Persistent Mounting Options After System Reboot

Because Wi-Fi arrays drop active network sessions upon system restart or extended sleep, the hidden volume must be remounted before Time Machine can run its scheduled cycles.

### Option A: The Automated Method (macOS Login Item)
This method ensures the hidden share maps and mounts automatically every time you log into your Mac desktop.

1. Mount your hidden network share manually via **Cmd + K** (`smb://[NAS_IP]/MacBackup$`).
2. Double-click the `.sparsebundle` file inside the share to mount the virtual `Time Machine` drive.
3. Open **System Settings** > **General** > **Login Items**.
4. In the **Open at Login** table, click the **+ (Plus)** button.
5. Navigate to your mounted hidden NAS folder, select the `MyTimeMachine.sparsebundle` file, and click **Add**.

### Option B: The Automated Method (Apple Shortcuts App)
For laptops or systems where network environments switch frequently, an Apple Shortcut provides a cleaner automation route.

1. Open the native **Shortcuts** app on macOS.
2. Click the **+** icon to create a new Shortcut and name it `Mount Time Machine NAS`.
3. In the action search bar on the right side, search for and add the **Connect to Server** action.
4. Input your hidden path into the action: `smb://[NAS_IP]/MacBackup$`.
5. Search for and append the **Open File** action immediately beneath it. Set the target file path to point directly to the `MyTimeMachine.sparsebundle` container located inside that server share.

### Option C: The Manual Terminal Command
If you prefer checking connections explicitly or deploying scripts via shell, execute this manually within **Terminal**:

```bash
# Create local mount entry directories
mkdir -p ~/mounts/MacBackup

# Mount the hidden network share directly using the targeted credentials
mount_smb //tm_user@[NAS_IP]/MacBackup$ ~/mounts/MacBackup

# Attach and mount the underlying sparsebundle drive container
hdiutil attach ~/mounts/MacBackup/MyTimeMachine.sparsebundle
```

---

## Part 5: Full-Profile Bare-Metal Disaster Recovery

If your Mac suffers an OS failure or requires a user-profile replacement, third-party restoration pipelines break. This container preserves complete system native recovery:

1. Boot your new or wiped Mac and progress through the initial language and region setup wizards until you reach a fresh desktop.
2. Ensure you are connected to the local network infrastructure.
3. Press **Cmd + K**, input your hidden share path (`smb://[NAS_IP]/MacBackup$`), and mount it.
4. Double-click the `MyTimeMachine.sparsebundle` container to mount the `Time Machine` volume disk.
5. Open **Migration Assistant** (`/Applications/Utilities/Migration Assistant`).
6. Select **From a Mac, Time Machine backup, or Startup disk**.
7. Migration Assistant will scan your local file hierarchy, detect the mounted virtual sparsebundle image, and treat it as a direct physical hardware connection—fully importing your historic system states, root profiles, and configurations.
