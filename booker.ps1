<#
.SYNOPSIS
Interactive AD user creation script.

.DESCRIPTION
- Verifies the current user can create AD users and modify group membership.
- Prompts for one or more users.
- Prompts whether all users share the same groups.
- For each user, interactively collects properties (names, UPN, department, title/role, etc.).
- Creates the AD user, then adds to specified groups.
#>

# Ensure the ActiveDirectory module is available and import it
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Error "The ActiveDirectory module is not available on this system. Install RSAT / AD tools and try again."
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

function Test-AdUserProvisionPermission {
    <#
    .SYNOPSIS
    Quick check that the current user can read and create AD objects and modify group membership.
    #>
    param(
        [string]$TestOuDN = "CN=Users," + (Get-ADDomain).DistinguishedName
    )

    try {
        # Check basic read access
        $null = Get-ADUser -Filter * -ResultSetSize 1 -ErrorAction Stop

        # Try a permission-like operation in a safe way:
        # 1. Create a test user in the default Users container (disabled, random name).
        # 2. Create a temporary global group.
        # 3. Try adding the test user to the group.
        # 4. Clean up.
        $guid = [Guid]::NewGuid().ToString("N")
        $testSam  = "perm_test_$guid"
        $testName = "Perm Test User $guid"
        $testGroupSam  = "perm_test_grp_$guid"
        $testGroupName = "Perm Test Group $guid"

        Write-Host "Performing permission self-check with temporary objects..." -ForegroundColor Yellow

        $securePass = ConvertTo-SecureString ([System.Web.Security.Membership]::GeneratePassword(12,2)) -AsPlainText -Force

        $testUser = New-ADUser -Name $testName `
                               -SamAccountName $testSam `
                               -AccountPassword $securePass `
                               -Enabled:$false `
                               -Path $TestOuDN `
                               -PassThru `
                               -ErrorAction Stop

        $testGroup = New-ADGroup -Name $testGroupName `
                                 -SamAccountName $testGroupSam `
                                 -GroupScope Global `
                                 -Path $TestOuDN `
                                 -PassThru `
                                 -ErrorAction Stop

        Add-ADGroupMember -Identity $testGroup.DistinguishedName -Members $testUser.DistinguishedName -ErrorAction Stop

        # Cleanup
        Remove-ADGroup -Identity $testGroup.DistinguishedName -Confirm:$false -ErrorAction SilentlyContinue
        Remove-ADUser  -Identity $testUser.DistinguishedName  -Confirm:$false -ErrorAction SilentlyContinue

        Write-Host "Permission check passed. You appear to have rights to create users and manage groups." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Permission check failed. The current account likely does not have rights to create users and/or manage groups. Details: $($_.Exception.Message)"
        return $false
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [switch]$DefaultYes
    )
    while ($true) {
        if ($DefaultYes) {
            $answer = Read-Host "$Prompt [Y/n]"
            if ([string]::IsNullOrWhiteSpace($answer)) { return $true }
        } else {
            $answer = Read-Host "$Prompt [y/N]"
            if ([string]::IsNullOrWhiteSpace($answer)) { return $false }
        }

        switch ($answer.ToLower()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default { Write-Host "Please answer y or n." -ForegroundColor Yellow }
        }
    }
}

# ----- MAIN -----

Write-Host "=== Interactive Active Directory User Creation ===" -ForegroundColor Cyan

# Check permissions first
if (-not (Test-AdUserProvisionPermission)) {
    Write-Host "Exiting due to insufficient permissions." -ForegroundColor Red
    exit 1
}

# Number of users
[int]$userCount = 0
while ($userCount -le 0) {
    $inputCount = Read-Host "How many users would you like to create?"
    if ([int]::TryParse($inputCount, [ref]$userCount)) {
        if ($userCount -le 0) {
            Write-Host "Please enter a number greater than 0." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Please enter a valid integer." -ForegroundColor Yellow
    }
}

# Decide group assignment mode
$useSameGroups = Read-YesNo -Prompt "Will all users be added to the same group(s)?" -DefaultYes

# Collect group(s) if they are the same for all users
$commonGroups = @()
if ($useSameGroups) {
    Write-Host "Enter one or more group names (SamAccountName, Name, or distinguishedName)." -ForegroundColor Cyan
    Write-Host "Press ENTER on a blank line when finished." -ForegroundColor DarkCyan

    while ($true) {
        $g = Read-Host "Group name (blank to finish)"
        if ([string]::IsNullOrWhiteSpace($g)) { break }
        $commonGroups += $g
    }
}

# Process each user
for ($i = 1; $i -le $userCount; $i++) {
    Write-Host ""
    Write-Host "=== User $i of $userCount ===" -ForegroundColor Cyan

    # Basic properties
    $givenName = Read-Host "First name (GivenName)"
    $surname   = Read-Host "Last name (Surname)"
    $displayName = Read-Host "Display Name (leave blank to use '$givenName $surname')"
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = "$givenName $surname"
    }

    $samAccountName = Read-Host "sAMAccountName (e.g. $($givenName.ToLower()).$($surname.ToLower()))"
    $upn = Read-Host "UserPrincipalName (e.g. $samAccountName@yourdomain.local)"

    # Role / title
    $title = Read-Host "Role/Title for this user (e.g. 'Systems Administrator')"

    # Optional additional props
    $department = Read-Host "Department (optional, ENTER to skip)"
    $office     = Read-Host "Office (optional, ENTER to skip)"
    $description = Read-Host "Description (optional, ENTER to skip)"

    # OU / path
    $defaultPath = (Get-ADDomain).UsersContainer
    $ouPath = Read-Host "DistinguishedName of OU/Container (ENTER for default '$defaultPath')"
    if ([string]::IsNullOrWhiteSpace($ouPath)) {
        $ouPath = $defaultPath
    }

    # Password
    $setRandomPassword = Read-YesNo -Prompt "Generate a random password?" -DefaultYes
    if ($setRandomPassword) {
        Add-Type -AssemblyName System.Web
        $plainPassword = [System.Web.Security.Membership]::GeneratePassword(14,3)
        Write-Host "Generated password for $samAccountName : $plainPassword" -ForegroundColor Yellow
        $securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force
    } else {
        $securePassword = Read-Host "Enter password" -AsSecureString
        # Optionally confirm password here if desired
    }

    # Decide group(s) for this user
    $groupsForThisUser = @()
    if ($useSameGroups) {
        $groupsForThisUser = $commonGroups
    } else {
        Write-Host "Enter group(s) for this user. Press ENTER on a blank line when finished." -ForegroundColor Cyan
        while ($true) {
            $g = Read-Host "Group name (blank to finish)"
            if ([string]::IsNullOrWhiteSpace($g)) { break }
            $groupsForThisUser += $g
        }
    }

    # Confirm summary
    Write-Host ""
    Write-Host "User summary:" -ForegroundColor DarkCyan
    Write-Host " Name:            $displayName"
    Write-Host " GivenName:       $givenName"
    Write-Host " Surname:         $surname"
    Write-Host " sAMAccountName:  $samAccountName"
    Write-Host " UPN:             $upn"
    Write-Host " Role/Title:      $title"
    Write-Host " Department:      $department"
    Write-Host " Office:          $office"
    Write-Host " Description:     $description"
    Write-Host " OU Path:         $ouPath"
    Write-Host " Groups:          $($groupsForThisUser -join ', ')"
    $proceed = Read-YesNo -Prompt "Create this user?" -DefaultYes
    if (-not $proceed) {
        Write-Host "Skipping user $samAccountName." -ForegroundColor Yellow
        continue
    }

    # Create the user
    try {
        # Check if user already exists
        $existingUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -ErrorAction SilentlyContinue
        if ($existingUser) {
            Write-Host "User with sAMAccountName '$samAccountName' already exists. Skipping creation." -ForegroundColor Red
            continue
        }

        $newUserParams = @{
            Name               = $displayName
            GivenName          = $givenName
            Surname            = $surname
            SamAccountName     = $samAccountName
            UserPrincipalName  = $upn
            DisplayName        = $displayName
            Enabled            = $true
            AccountPassword    = $securePassword
            Path               = $ouPath
            ChangePasswordAtLogon = $true
            PassThru           = $true
        }

        if ($title)      { $newUserParams['Title']       = $title }
        if ($department) { $newUserParams['Department']  = $department }
        if ($office)     { $newUserParams['Office']      = $office }
        if ($description){ $newUserParams['Description'] = $description }

        $newUser = New-ADUser @newUserParams
        Write-Host "Successfully created user '$($newUser.SamAccountName)'." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to create user '$samAccountName'. Error: $($_.Exception.Message)"
        continue
    }

    # Add to groups
    foreach ($grp in $groupsForThisUser) {
        if ([string]::IsNullOrWhiteSpace($grp)) { continue }

        try {
            $groupObj = Get-ADGroup -Identity $grp -ErrorAction Stop
        }
        catch {
            Write-Host "Group '$grp' not found. Skipping for this user." -ForegroundColor Yellow
            continue
        }

        try {
            Add-ADGroupMember -Identity $groupObj.DistinguishedName -Members $newUser.DistinguishedName -ErrorAction Stop
            Write-Host "Added '$($newUser.SamAccountName)' to group '$($groupObj.SamAccountName)'." -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to add '$($newUser.SamAccountName)' to group '$grp'. Error: $($_.Exception.Message)"
        }
    }
}

Write-Host ""
Write-Host "All requested users processed." -ForegroundColor Cyan
