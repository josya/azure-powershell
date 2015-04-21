﻿# ----------------------------------------------------------------------------------
#
# Copyright Microsoft Corporation
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------------

<#
.SYNOPSIS
Test Virtual Machines
#>
function Test-VirtualMachine
{
    # Setup
    $rgname = Get-ComputeTestResourceName

    try
    {
        # Common
        $loc = 'West US';
        New-AzureResourceGroup -Name $rgname -Location $loc;
        
        # VM Profile & Hardware
        $vmsize = 'Standard_A2';
        $vmname = 'vm' + $rgname;
        $p = New-AzureVMConfig -VMName $vmname -VMSize $vmsize;
        Assert-AreEqual $p.HardwareProfile.VirtualMachineSize $vmsize;

        # NRP
        $subnet = New-AzureVirtualNetworkSubnetConfig -Name ('subnet' + $rgname) -AddressPrefix "10.0.0.0/24";
        $vnet = New-AzureVirtualNetwork -Force -Name ('vnet' + $rgname) -ResourceGroupName $rgname -Location $loc -AddressPrefix "10.0.0.0/16" -DnsServer "10.1.1.1" -Subnet $subnet;
        $vnet = Get-AzureVirtualNetwork -Name ('vnet' + $rgname) -ResourceGroupName $rgname;
        $subnetId = $vnet.Subnets[0].Id;
        $pubip = New-AzurePublicIpAddress -Force -Name ('pubip' + $rgname) -ResourceGroupName $rgname -Location $loc -AllocationMethod Dynamic -DomainNameLabel ('pubip' + $rgname);
        $pubip = Get-AzurePublicIpAddress -Name ('pubip' + $rgname) -ResourceGroupName $rgname;
        $pubipId = $pubip.Id;
        $nic = New-AzureNetworkInterface -Force -Name ('nic' + $rgname) -ResourceGroupName $rgname -Location $loc -SubnetId $subnetId -PublicIpAddressId $pubip.Id;
        $nic = Get-AzureNetworkInterface -Name ('nic' + $rgname) -ResourceGroupName $rgname;
        $nicId = $nic.Id;

        $p = Add-AzureVMNetworkInterface -VM $p -Id $nicId;
        Assert-AreEqual $p.NetworkProfile.NetworkInterfaces.Count 1;
        Assert-AreEqual $p.NetworkProfile.NetworkInterfaces[0].ReferenceUri $nicId;

        # Storage Account (SA)
        $stoname = 'sto' + $rgname;
        $stotype = 'Standard_GRS';
        New-AzureStorageAccount -ResourceGroupName $rgname -Name $stoname -Location $loc -Type $stotype;
        $stoaccount = Get-AzureStorageAccount -ResourceGroupName $rgname -Name $stoname;

        $osDiskName = 'osDisk';
        $osDiskCaching = 'ReadWrite';
        $osDiskVhdUri = "https://$stoname.blob.core.windows.net/test/os.vhd";
        $dataDiskVhdUri1 = "https://$stoname.blob.core.windows.net/test/data1.vhd";
        $dataDiskVhdUri2 = "https://$stoname.blob.core.windows.net/test/data2.vhd";
        $dataDiskVhdUri3 = "https://$stoname.blob.core.windows.net/test/data3.vhd";

        $p = Set-AzureVMOSDisk -VM $p -Name $osDiskName -VhdUri $osDiskVhdUri -Caching $osDiskCaching;

        $p = Add-AzureVMDataDisk -VM $p -Name 'testDataDisk1' -Caching 'ReadOnly' -DiskSizeInGB 10 -Lun 0 -VhdUri $dataDiskVhdUri1;
        $p = Add-AzureVMDataDisk -VM $p -Name 'testDataDisk2' -Caching 'ReadOnly' -DiskSizeInGB 11 -Lun 1 -VhdUri $dataDiskVhdUri2;
        $p = Add-AzureVMDataDisk -VM $p -Name 'testDataDisk3' -Caching 'ReadOnly' -DiskSizeInGB 12 -Lun 2 -VhdUri $dataDiskVhdUri3;
        $p = Remove-AzureVMDataDisk -VM $p -Name 'testDataDisk3';
        
        Assert-AreEqual $p.StorageProfile.OSDisk.Caching $osDiskCaching;
        Assert-AreEqual $p.StorageProfile.OSDisk.Name $osDiskName;
        Assert-AreEqual $p.StorageProfile.OSDisk.VirtualHardDisk.Uri $osDiskVhdUri;
        Assert-AreEqual $p.StorageProfile.DataDisks.Count 2;
        Assert-AreEqual $p.StorageProfile.DataDisks[0].Caching 'ReadOnly';
        Assert-AreEqual $p.StorageProfile.DataDisks[0].DiskSizeGB 10;
        Assert-AreEqual $p.StorageProfile.DataDisks[0].Lun 0;
        Assert-AreEqual $p.StorageProfile.DataDisks[0].VirtualHardDisk.Uri $dataDiskVhdUri1;
        Assert-AreEqual $p.StorageProfile.DataDisks[1].Caching 'ReadOnly';
        Assert-AreEqual $p.StorageProfile.DataDisks[1].DiskSizeGB 11;
        Assert-AreEqual $p.StorageProfile.DataDisks[1].Lun 1;
        Assert-AreEqual $p.StorageProfile.DataDisks[1].VirtualHardDisk.Uri $dataDiskVhdUri2;

        # OS & Image
        $user = "Foo12";
        $password = 'BaR@123' + $rgname;
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force;
        $cred = New-Object System.Management.Automation.PSCredential ($user, $securePassword);
        $computerName = 'test';
        $vhdContainer = "https://$stoname.blob.core.windows.net/test";
        $img = 'a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-Datacenter-201503.01-en.us-127GB.vhd';

        $p.StorageProfile.OSDisk = $null;
        $p = Set-AzureVMOperatingSystem -VM $p -Windows -ComputerName $computerName -Credential $cred;
        $p = Set-AzureVMSourceImage -VM $p -Name $img;

        Assert-AreEqual $p.OSProfile.AdminUsername $user;
        Assert-AreEqual $p.OSProfile.ComputerName $computerName;
        Assert-AreEqual $p.OSProfile.AdminPassword $password;
        Assert-AreEqual $p.StorageProfile.SourceImage.ReferenceUri ('/' + (Get-AzureSubscription -Current).SubscriptionId + '/services/images/' + $img);

        # Virtual Machine
        # TODO: Still need to do retry for New-AzureVM for SA, even it's returned in Get-.
        New-AzureVM -ResourceGroupName $rgname -Location $loc -Name $vmname -VM $p;

        # Get VM
        $vm1 = Get-AzureVM -Name $vmname -ResourceGroupName $rgname;
        Assert-AreEqual $vm1.Name $vmname;
        Assert-AreEqual $vm1.NetworkProfile.NetworkInterfaces.Count 1;
        Assert-AreEqual $vm1.NetworkProfile.NetworkInterfaces[0].ReferenceUri $nicId;
        Assert-AreEqual $vm1.StorageProfile.SourceImage.ReferenceUri ('/' + (Get-AzureSubscription -Current).SubscriptionId + '/services/images/' + $img);
        Assert-AreEqual $vm1.OSProfile.AdminUsername $user;
        Assert-AreEqual $vm1.OSProfile.ComputerName $computerName;
        Assert-AreEqual $vm1.HardwareProfile.VirtualMachineSize $vmsize;

        Start-AzureVM -Name $vmname -ResourceGroupName $rgname;
        Restart-AzureVM -Name $vmname -ResourceGroupName $rgname;
        Stop-AzureVM -Name $vmname -ResourceGroupName $rgname -Force -StayProvisioned;

        # Update
        $p.Location = $vm1.Location;
        Update-AzureVM -ResourceGroupName $rgname -Name $vmname -VM $p;

        $vm2 = Get-AzureVM -Name $vmname -ResourceGroupName $rgname;
        Assert-AreEqual $vm2.NetworkProfile.NetworkInterfaces.Count 1;
        Assert-AreEqual $vm2.NetworkProfile.NetworkInterfaces[0].ReferenceUri $nicId;
        Assert-AreEqual $vm2.StorageProfile.SourceImage.ReferenceUri ('/' + (Get-AzureSubscription -Current).SubscriptionId + '/services/images/' + $img);
        Assert-AreEqual $vm2.OSProfile.AdminUsername $user;
        Assert-AreEqual $vm2.OSProfile.ComputerName $computerName;
        Assert-AreEqual $vm2.HardwareProfile.VirtualMachineSize $vmsize;
        Assert-NotNull $vm2.Location;
        
        $vms = Get-AzureVM -ResourceGroupName $rgname;
        Assert-AreNotEqual $vms $null;

        # Remove All VMs
        Get-AzureVM -ResourceGroupName $rgname | Remove-AzureVM -ResourceGroupName $rgname -Force;
        $vms = Get-AzureVM -ResourceGroupName $rgname;
        Assert-AreEqual $vms $null;

        # Availability Set
        $asetName = 'aset' + $rgname;
        New-AzureAvailabilitySet -ResourceGroupName $rgname -Name $asetName -Location $loc;

        $asets = Get-AzureAvailabilitySet -ResourceGroupName $rgname;
        Assert-NotNull $asets;
        Assert-AreEqual $asetName $asets[0].Name;

        $aset = Get-AzureAvailabilitySet -ResourceGroupName $rgname -Name $asetName;
        Assert-NotNull $aset;
        Assert-AreEqual $asetName $aset.Name;

        $asetId = ('/subscriptions/' + (Get-AzureSubscription -Current).SubscriptionId + '/resourceGroups/' + $rgname + '/providers/Microsoft.Compute/availabilitySets/' + $asetName);
        $vmname2 = $vmname + '2';
        $p2 = New-AzureVMConfig -VMName $vmname2 -VMSize $vmsize -AvailabilitySetId $asetId;
        $p2.HardwareProfile = $p.HardwareProfile;
        $p2.OSProfile = $p.OSProfile;
        $p2.NetworkProfile = $p.NetworkProfile;
        $p2.StorageProfile = $p.StorageProfile;
        New-AzureVM -ResourceGroupName $rgname -Location $loc -VM $p2;

        $vm2 = Get-AzureVM -Name $vmname2 -ResourceGroupName $rgname;
        Assert-NotNull $vm2;
        Assert-AreEqual $vm2.AvailabilitySetId $asetId;
        
        # Remove
        Remove-AzureVM -Name $vmname2 -ResourceGroupName $rgname -Force;
    }
    finally
    {
        # Cleanup
        Clean-ResourceGroup $rgname
    }
}

<#
.SYNOPSIS
Test Virtual Machine Size and Usage
#>
function Test-VirtualMachineList
{
    # Setup
    $passed = $false;

    try
    {
        $s1 = Get-AzureVM -All;
        $s2 = Get-AzureVM;

        Assert-ThrowsContains { $s3 = Get-AzureVM -NextLink "http://www.test.com/test"; } "Unexpected character"

        $passed = $true;
    }
    finally
    {
        Assert-True { $passed };
    }
}

<#
.SYNOPSIS
Test Virtual Machine Size and Usage
#>
function Test-VirtualMachineImageList
{
    # Setup
    $passed = $false;

    try
    {
        $locStr = 'EastAsia';

        # List Tests
        $foundAnyImage = $false;
        $pubNames = Get-AzureVMImagePublisher -Location $locStr | select -ExpandProperty Resources | select -ExpandProperty Name;
        $maxPubCheck = 3;
        $numPubCheck = 1;
        $pubNameFilter = '*Windows*';
        foreach ($pub in $pubNames)
        {
            # Filter Windows Images
            if (-not ($pub -like $pubNameFilter)) { continue; }

            $s2 = Get-AzureVMImageOffer -Location $locStr -PublisherName $pub;
            if ($s2.Resources.Count -gt 0)
            {
                # Check "$maxPubCheck" publishers at most
                $numPubCheck = $numPubCheck + 1;
                if ($numPubCheck -gt $maxPubCheck) { break; }

                $offerNames = $s2.Resources | select -ExpandProperty Name;
                foreach ($offer in $offerNames)
                {
                    $s3 = Get-AzureVMImageSku -Location $locStr -PublisherName $pub -Offer $offer;
                    if ($s3.Resources.Count -gt 0)
                    {
                        $skus = $s3.Resources | select -ExpandProperty Name;
                        foreach ($sku in $skus)
                        {
                            $s4 = Get-AzureVMImage -Location $locStr -PublisherName $pub -Offer $offer -Sku $sku;
                            if ($s4.Resources.Count -gt 0)
                            {
                                $versions = $s4.Resources | select -ExpandProperty Name;

                                $s6 = Get-AzureVMImage -Location $locStr -PublisherName $pub -Offer $offer -Sku $sku -FilterExpression ('name -eq *');
                                Assert-NotNull $s6;
                                Assert-NotNull $s6.Resources;
                                $verNames = $s6.Resources | select -ExpandProperty Name;

                                foreach ($ver in $versions)
                                {
                                    $s6 = Get-AzureVMImage -Location $locStr -PublisherName $pub -Offer $offer -Sku $sku -Version $ver;
                                    Assert-NotNull $s6;
                                    Assert-NotNull $s6.VirtualMachineImage;
                                    $s6.VirtualMachineImage;

                                    Assert-True { $verNames -contains $ver };
                                    Assert-True { $verNames -contains $s6.VirtualMachineImage.Name };

                                    $s6.VirtualMachineImage.Id;

                                    $foundAnyImage = $true;
                                }
                            }
                        }
                    }
                }
            }
        }

        Assert-True { $foundAnyImage };

        # Test Extension Image
        $foundAnyExtensionImage = $false;
        $pubNameFilter = '*Microsoft.Compute*';

        foreach ($pub in $pubNames)
        {
            # Filter Windows Images
            if (-not ($pub -like $pubNameFilter)) { continue; }

            $s1 = Get-AzureVMExtensionImageType -Location $locStr -PublisherName $pub;
            $types = $s1.Resources | select -ExpandProperty Name;
            if ($types.Count -gt 0)
            {
                foreach ($type in $types)
                {
                    $s2 = Get-AzureVMExtensionImageVersion -Location $locStr -PublisherName $pub -Type $type -FilterExpression '*';
                    $versions = $s2.Resources | select -ExpandProperty Name;
                    foreach ($ver in $versions)
                    {
                        $s3 = Get-AzureVMExtensionImage -Location $locStr -PublisherName $pub -Type $type -Version $ver -FilterExpression '*';
                
                        Assert-NotNull $s3;
                        Assert-NotNull $s3.VirtualMachineExtensionImage;
                        Assert-True { $s3.VirtualMachineExtensionImage.Name -eq $ver; }
                        
                        $s3.VirtualMachineExtensionImage.Id;

                        $foundAnyExtensionImage = $true;
                    }
                }
            }
        }

        Assert-True { $foundAnyExtensionImage };

        # Negative Tests
        # VM Images
        $s1 = Get-AzureVMImagePublisher -Location $locStr;
        Assert-NotNull $s1;

        $publisherName = Get-ComputeTestResourceName;
        Assert-ThrowsContains { $s2 = Get-AzureVMImageOffer -Location $locStr -PublisherName $publisherName; } "$publisherName was not found";

        $offerName = Get-ComputeTestResourceName;
        Assert-ThrowsContains { $s3 = Get-AzureVMImageSku -Location $locStr -PublisherName $publisherName -Offer $offerName; } "$offerName was not found";
        
        $skusName = Get-ComputeTestResourceName;
        Assert-ThrowsContains { $s4 = Get-AzureVMImage -Location $locStr -PublisherName $publisherName -Offer $offerName -Skus $skusName; } "$skusName was not found";

        $filter = "name eq 'latest'";
        Assert-ThrowsContains { $s5 = Get-AzureVMImage -Location $locStr -PublisherName $publisherName -Offer $offerName -Skus $skusName -FilterExpression $filter; } "was not found";

        $version = '1.0.0';
        Assert-ThrowsContains { $s6 = Get-AzureVMImage -Location $locStr -PublisherName $publisherName -Offer $offerName -Skus $skusName -Version $version; } "was not found";

        # Extension Images
        $type = Get-ComputeTestResourceName;
        Assert-ThrowsContains { $s7 = Get-AzureVMExtensionImage -Location $locStr -PublisherName $publisherName -Type $type -FilterExpression $filter -Version $version; } "was not found";
        
        Assert-ThrowsContains { $s8 = Get-AzureVMExtensionImageType -Location $locStr -PublisherName $publisherName; } "was not found";

        Assert-ThrowsContains { $s9 = Get-AzureVMExtensionImageVersion -Location $locStr -PublisherName $publisherName -Type $type -FilterExpression $filter; } "was not found";

        $passed = $true;
    }
    finally
    {
        #Assert-True { $passed };
    }
}

<#
.SYNOPSIS
Test Virtual Machine Size and Usage
#>
function Test-VirtualMachineSizeAndUsage
{
    # Setup
    $rgname = Get-ComputeTestResourceName
    $passed = $false;

    try
    {
        # Common
        $loc = 'West US';
        New-AzureResourceGroup -Name $rgname -Location $loc;
        
        # Availability Set
        $asetName = 'aset' + $rgname;
        New-AzureAvailabilitySet -ResourceGroupName $rgname -Name $asetName -Location $loc;

        $asets = Get-AzureAvailabilitySet -ResourceGroupName $rgname;
        Assert-NotNull $asets;
        Assert-AreEqual $asetName $asets[0].Name;

        $aset = Get-AzureAvailabilitySet -ResourceGroupName $rgname -Name $asetName;
        Assert-NotNull $aset;
        Assert-AreEqual $asetName $aset.Name;

        $asetId = ('/subscriptions/' + (Get-AzureSubscription -Current).SubscriptionId + '/resourceGroups/' + $rgname + '/providers/Microsoft.Compute/availabilitySets/' + $asetName);

        # VM Profile & Hardware
        $vmsize = 'Standard_A2';
        $vmname = 'vm' + $rgname;
        $p = New-AzureVMConfig -VMName $vmname -VMSize $vmsize -AvailabilitySetId $asetId;
        Assert-AreEqual $p.HardwareProfile.VirtualMachineSize $vmsize;

        # NRP
        $subnet = New-AzureVirtualNetworkSubnetConfig -Name ('subnet' + $rgname) -AddressPrefix "10.0.0.0/24";
        $vnet = New-AzureVirtualNetwork -Force -Name ('vnet' + $rgname) -ResourceGroupName $rgname -Location $loc -AddressPrefix "10.0.0.0/16" -DnsServer "10.1.1.1" -Subnet $subnet;
        $vnet = Get-AzureVirtualNetwork -Name ('vnet' + $rgname) -ResourceGroupName $rgname;
        $subnetId = $vnet.Subnets[0].Id;
        $pubip = New-AzurePublicIpAddress -Force -Name ('pubip' + $rgname) -ResourceGroupName $rgname -Location $loc -AllocationMethod Dynamic -DomainNameLabel ('pubip' + $rgname);
        $pubip = Get-AzurePublicIpAddress -Name ('pubip' + $rgname) -ResourceGroupName $rgname;
        $pubipId = $pubip.Id;
        $nic = New-AzureNetworkInterface -Force -Name ('nic' + $rgname) -ResourceGroupName $rgname -Location $loc -SubnetId $subnetId -PublicIpAddressId $pubip.Id;
        $nic = Get-AzureNetworkInterface -Name ('nic' + $rgname) -ResourceGroupName $rgname;
        $nicId = $nic.Id;

        $p = Add-AzureVMNetworkInterface -VM $p -Id $nicId;
        Assert-AreEqual $p.NetworkProfile.NetworkInterfaces.Count 1;
        Assert-AreEqual $p.NetworkProfile.NetworkInterfaces[0].ReferenceUri $nicId;

        # Storage Account (SA)
        $stoname = 'sto' + $rgname;
        $stotype = 'Standard_GRS';
        New-AzureStorageAccount -ResourceGroupName $rgname -Name $stoname -Location $loc -Type $stotype;
        $stoaccount = Get-AzureStorageAccount -ResourceGroupName $rgname -Name $stoname;

        $osDiskName = 'osDisk';
        $osDiskCaching = 'ReadWrite';
        $osDiskVhdUri = "https://$stoname.blob.core.windows.net/test/os.vhd";
        $dataDiskVhdUri1 = "https://$stoname.blob.core.windows.net/test/data1.vhd";
        $dataDiskVhdUri2 = "https://$stoname.blob.core.windows.net/test/data2.vhd";
        $dataDiskVhdUri3 = "https://$stoname.blob.core.windows.net/test/data3.vhd";

        $p = Set-AzureVMOSDisk -VM $p -Name $osDiskName -VhdUri $osDiskVhdUri -Caching $osDiskCaching;

        $p = Add-AzureVMDataDisk -VM $p -Name 'testDataDisk1' -Caching 'ReadOnly' -DiskSizeInGB 10 -Lun 0 -VhdUri $dataDiskVhdUri1;
        $p = Add-AzureVMDataDisk -VM $p -Name 'testDataDisk2' -Caching 'ReadOnly' -DiskSizeInGB 11 -Lun 1 -VhdUri $dataDiskVhdUri2;
        $p = Add-AzureVMDataDisk -VM $p -Name 'testDataDisk3' -Caching 'ReadOnly' -DiskSizeInGB 12 -Lun 2 -VhdUri $dataDiskVhdUri3;
        $p = Remove-AzureVMDataDisk -VM $p -Name 'testDataDisk3';
        
        Assert-AreEqual $p.StorageProfile.OSDisk.Caching $osDiskCaching;
        Assert-AreEqual $p.StorageProfile.OSDisk.Name $osDiskName;
        Assert-AreEqual $p.StorageProfile.OSDisk.VirtualHardDisk.Uri $osDiskVhdUri;
        Assert-AreEqual $p.StorageProfile.DataDisks.Count 2;
        Assert-AreEqual $p.StorageProfile.DataDisks[0].Caching 'ReadOnly';
        Assert-AreEqual $p.StorageProfile.DataDisks[0].DiskSizeGB 10;
        Assert-AreEqual $p.StorageProfile.DataDisks[0].Lun 0;
        Assert-AreEqual $p.StorageProfile.DataDisks[0].VirtualHardDisk.Uri $dataDiskVhdUri1;
        Assert-AreEqual $p.StorageProfile.DataDisks[1].Caching 'ReadOnly';
        Assert-AreEqual $p.StorageProfile.DataDisks[1].DiskSizeGB 11;
        Assert-AreEqual $p.StorageProfile.DataDisks[1].Lun 1;
        Assert-AreEqual $p.StorageProfile.DataDisks[1].VirtualHardDisk.Uri $dataDiskVhdUri2;

        # OS & Image
        $user = "Foo12";
        $password = 'BaR@123' + $rgname;
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force;
        $cred = New-Object System.Management.Automation.PSCredential ($user, $securePassword);
        $computerName = 'test';
        $vhdContainer = "https://$stoname.blob.core.windows.net/test";
        $img = 'a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-Datacenter-201503.01-en.us-127GB.vhd';

        $p.StorageProfile.OSDisk = $null;
        $p = Set-AzureVMOperatingSystem -VM $p -Windows -ComputerName $computerName -Credential $cred;
        $p = Set-AzureVMSourceImage -VM $p -Name $img;

        Assert-AreEqual $p.OSProfile.AdminUsername $user;
        Assert-AreEqual $p.OSProfile.ComputerName $computerName;
        Assert-AreEqual $p.OSProfile.AdminPassword $password;
        Assert-AreEqual $p.StorageProfile.SourceImage.ReferenceUri ('/' + (Get-AzureSubscription -Current).SubscriptionId + '/services/images/' + $img);

        # Create VM
        New-AzureVM -ResourceGroupName $rgname -Location $loc -Name $vmname -VM $p;

        # Get VM
        $vm1 = Get-AzureVM -Name $vmname -ResourceGroupName $rgname;
        Assert-AreEqual $vm1.Name $vmname;
        Assert-AreEqual $vm1.NetworkProfile.NetworkInterfaces.Count 1;
        Assert-AreEqual $vm1.NetworkProfile.NetworkInterfaces[0].ReferenceUri $nicId;
        Assert-AreEqual $vm1.StorageProfile.SourceImage.ReferenceUri ('/' + (Get-AzureSubscription -Current).SubscriptionId + '/services/images/' + $img);
        Assert-AreEqual $vm1.OSProfile.AdminUsername $user;
        Assert-AreEqual $vm1.OSProfile.ComputerName $computerName;
        Assert-AreEqual $vm1.HardwareProfile.VirtualMachineSize $vmsize;

        # Test Sizes
        $s1 = Get-AzureVMSize -Location ($loc -replace ' ');
        Assert-NotNull $s1;
        Validate-VirtualMachineSize $vmsize $s1;

        $s2 = Get-AzureVMSize -ResourceGroupName $rgname -VMName $vmname;
        Assert-NotNull $s2;
        Validate-VirtualMachineSize $vmsize $s2;

        $s3 = Get-AzureVMSize -ResourceGroupName $rgname -AvailabilitySetName $asetName;
        Assert-NotNull $s3;
        Validate-VirtualMachineSize $vmsize $s3;

        # Test Usage
        $u1 = Get-AzureVMUsage -Location ($loc -replace ' ');
        Validate-VirtualMachineUsage $u1.Usages;

        $passed = $true;
    }
    finally
    {
        Assert-True { $passed };

        # Cleanup
        Clean-ResourceGroup $rgname
    }
}

function Validate-VirtualMachineSize
{
    param([string] $vmSize, $vmSizeList)

    $count = 0;

    foreach ($item in $vmSizeList)
    {
        if ($item.Name -eq $vmSize)
        {
            $count = $count + 1;
        }
    }

    $valid = $count -eq 1;

    return $valid;
}

function Validate-VirtualMachineUsage
{
    param($vmUsageList)

    $valid = $true;

    foreach ($item in $vmUsageList)
    {
        Assert-NotNull $item;
        Assert-NotNull $item.Name;
        Assert-NotNull $item.Name.Value;
        Assert-NotNull $item.Name.LocalizedValue;
        Assert-True { $item.CurrentValue -le $item.Limit };
    }

    return $valid;
}
