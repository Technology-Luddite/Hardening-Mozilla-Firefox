Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- Firefox Profile Detection ---
$profileRoot = "$env:APPDATA\Mozilla\Firefox\Profiles"
$profile = Get-ChildItem $profileRoot -Directory |
    Where-Object { $_.Name -match "default-release" -or $_.Name -match "default" } |
    Select-Object -First 1

if (-not $profile) {
    [System.Windows.Forms.MessageBox]::Show("No Firefox profile found. Please run Firefox at least once.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

$path = Join-Path $profile.FullName "user.js"

# Read existing user.js content to check current states (or use empty string if file doesn't exist)
$existingContent = ""
if (Test-Path $path) {
    $existingContent = Get-Content $path -Raw
}

# --- Define Settings Categories ---
# Using strict key lookups to dynamically check if settings are already configured
$categories = [ordered]@{
    "Telemetry & Data Reporting" = @{
        Key = "toolkit.telemetry.enabled"
        Prefs = @'
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.healthreport.service.enabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.sessions.current.clean", true);
user_pref("breakpad.reportURL", "");
user_pref("browser.tabs.crashReporting.sendReport", false);
user_pref("toolkit.telemetry.server", "");
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.hybridContent.enabled", false);
user_pref("toolkit.telemetry.unifiedIsOptIn", false);
user_pref("toolkit.telemetry.prompted", 2);
user_pref("toolkit.telemetry.rejected", true);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);
user_pref("browser.ping-centre.telemetry", false);
user_pref("devtools.onboarding.telemetry.logged", false);
'@
    }

    "UI Bloat, Pocket, & Sponsored Content" = @{
        Key = "extensions.pocket.enabled"
        Prefs = @'
user_pref("browser.newtabpage.activity-stream.showSponsored", false);
user_pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
user_pref("browser.newtabpage.activity-stream.feeds.snippets", false);
user_pref("browser.newtabpage.activity-stream.feeds.topsites", false);
user_pref("browser.newtabpage.activity-stream.section.highlights.includePocket", false);
user_pref("extensions.pocket.enabled", false);
'@
    }

    "Networking, Prefetching & IPv6 Disable" = @{
        Key = "network.prefetch-next"
        Prefs = @'
user_pref("network.prefetch-next", false);
user_pref("network.dns.disablePrefetch", true);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.predictor.enabled", false);
user_pref("network.dns.disableIPv6", true);
'@
    }

    "Search & URL Bar Hardening" = @{
        Key = "browser.urlbar.suggest.searches"
        Prefs = @'
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.search.suggest.enabled", false);
'@
    }

    "Extra Privacy & Tracking Protection" = @{
        Key = "geo.enabled"
        Prefs = @'
user_pref("geo.enabled", false);
user_pref("privacy.trackingprotection.enabled", true);
user_pref("privacy.trackingprotection.socialtracking.enabled", true);
'@
    }

    "WebRTC & Media Proxies" = @{
        Key = "media.navigator.enabled"
        Prefs = @'
user_pref("media.peerconnection.ice.default_address_only", true);
user_pref("media.peerconnection.enabled", false); 
user_pref("media.navigator.enabled", false);
'@
    }

    "Anti-Fingerprinting (Tor-Level & Video)" = @{
        Key = "privacy.resistFingerprinting"
        Prefs = @'
user_pref("privacy.resistFingerprinting", true);
user_pref("privacy.resistFingerprinting.overrides", "+JSDateTimeUTC");
user_pref("webgl.disabled", true);
user_pref("media.video_stats.enabled", false);
'@
    }

    "Anti-OS Font Leaks" = @{
        Key = "layout.css.font-visibility.private"
        Prefs = @'
user_pref("layout.css.font-visibility.private", 1);
user_pref("layout.css.font-visibility.standard", 1);
user_pref("layout.css.font-visibility.trackingprotection", 1);
'@
    }

    "Google SafeBrowsing De-linking" = @{
        Key = "browser.safebrowsing.malware.enabled"
        Prefs = @'
user_pref("browser.safebrowsing.downloads.remote.enabled", false);
user_pref("browser.safebrowsing.malware.enabled", false);
user_pref("browser.safebrowsing.phishing.enabled", false);
'@
    }

    "Misc (Set Homepage to Privacy Settings)" = @{
        Key = "browser.startup.homepage"
        Prefs = @'
user_pref("browser.startup.homepage", "about:preferences#privacy");
'@
    }
}

# --- Build the GUI Form Window ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Firefox Privacy & Hardening Manager - Version: 1.0"
$form.Size = New-Object System.Drawing.Size(480, 540)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Label Instructions
$label = New-Object System.Windows.Forms.Label
$label.Text = "Current settings detected from user.js configuration.`nModify selections and click Apply to update."
$label.Location = New-Object System.Drawing.Point(20, 15)
$label.Size = New-Object System.Drawing.Size(430, 40)
$form.Controls.Add($label)

# --- Scrollable Panel Container ---
$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(20, 70)
$panel.Size = New-Object System.Drawing.Size(425, 330)
$panel.AutoScroll = $true
$panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($panel)

# Dictionary to track checkbox objects dynamically
$checkboxes = @{}
$yOffset = 10

# Generate Checkboxes dynamically inside the panel
foreach ($key in $categories.Keys) {
    $checkBox = New-Object System.Windows.Forms.CheckBox
    $checkBox.Text = $key
    $checkBox.Location = New-Object System.Drawing.Point(15, $yOffset)
    $checkBox.Size = New-Object System.Drawing.Size(370, 25)
    
    # Robust scan check: Looks for the preference keyword name anywhere on an active config line
    if ($existingContent -match "user_pref\(\s*`"$($categories[$key].Key)`"\s*,") {
        $checkBox.Checked = $true
    } else {
        $checkBox.Checked = $false
    }
    
    $panel.Controls.Add($checkBox)
    $checkboxes[$key] = $checkBox
    $yOffset += 30
}

# Apply Button (Positioned safely below the scroll panel with clean margins)
$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = "Apply Changes"
$applyButton.Location = New-Object System.Drawing.Point(165, 435)
$applyButton.Size = New-Object System.Drawing.Size(140, 35)

# Button Click Event Logic
$applyButton.Add_Click({
    $finalSettings = New-Object System.Text.StringBuilder
    [void]$finalSettings.AppendLine("// --- Managed via GUI Hardening Tool ---")

    foreach ($key in $categories.Keys) {
        if ($checkboxes[$key].Checked) {
            [void]$finalSettings.AppendLine("// $key")
            [void]$finalSettings.AppendLine($categories[$key].Prefs)
        }
    }

    try {
        # Overwrite user.js cleanly with current choices
        [System.IO.File]::WriteAllText($path, $finalSettings.ToString())
        [System.Windows.Forms.MessageBox]::Show("Firefox preferences updated successfully!`n`nPlease fully close and restart Firefox to apply changes.", "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $form.Close()
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to save changes to user.js:`n$($_.Exception.Message)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$form.Controls.Add($applyButton)

# Display Form
[void]$form.ShowDialog()