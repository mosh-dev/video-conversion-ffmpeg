# ============================================================================
# MODERN WINDOWS 11 UI FOR QUALITY ANALYZER
# ============================================================================
# This file contains the UI logic for the quality analyzer tool
# Returns a hashtable with user-selected settings

function Show-QualityAnalyzerUI {
    param(
        [bool]$EnableVMAF,
        [bool]$EnableSSIM,
        [bool]$EnablePSNR,
        [int]$VMAF_Subsample
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    # Detect Windows theme (Dark/Light mode)
    function Get-WindowsTheme {
        try {
            $theme = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
            if ($theme.AppsUseLightTheme -eq 0) {
                return "Dark"
            } else {
                return "Light"
            }
        } catch {
            return "Light"
        }
    }

    # Get Windows accent color
    function Get-WindowsAccentColor {
        try {
            $accentColor = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "AccentColor" -ErrorAction SilentlyContinue
            if ($accentColor) {
                $color = $accentColor.AccentColor
                $r = $color -band 0xFF
                $g = ($color -shr 8) -band 0xFF
                $b = ($color -shr 16) -band 0xFF
                return "#{0:X2}{1:X2}{2:X2}" -f $r, $g, $b
            }
        } catch { }
        return "#0078D4"
    }

    $currentTheme = Get-WindowsTheme
    $accentColor = Get-WindowsAccentColor

    # Define colors based on theme
    if ($currentTheme -eq "Dark") {
        $backgroundColor = "#202020"
        $cardBackground = "#2B2B2B"
        $textColor = "#FFFFFF"
        $secondaryTextColor = "#B0B0B0"
        $borderColor = "#3F3F3F"
        $hoverBackground = "#333333"
        $infoBoxBg = "#1E3A5F"
        $infoBoxBorder = "#2B5278"
        $infoBoxText = "#6CB4FF"
    } else {
        $backgroundColor = "#F3F3F3"
        $cardBackground = "#FFFFFF"
        $textColor = "#1F1F1F"
        $secondaryTextColor = "#757575"
        $borderColor = "#E0E0E0"
        $hoverBackground = "#F5F5F5"
        $infoBoxBg = "#F0F7FF"
        $infoBoxBorder = "#C7E0F4"
        $infoBoxText = "#0078D4"
    }

    # XAML with Windows 11 styling
    [xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Width="600"
    Height="600"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent">

    <Window.Resources>
        <!-- Modern CheckBox Style -->
        <Style x:Key="ModernCheckBox" TargetType="CheckBox">
            <Setter Property="Foreground" Value="$textColor"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Border
                                x:Name="CheckBoxBorder"
                                Grid.Column="0"
                                Width="20"
                                Height="20"
                                Background="$cardBackground"
                                BorderBrush="$borderColor"
                                BorderThickness="2"
                                CornerRadius="4"
                                Margin="0,0,12,0">
                                <Path
                                    x:Name="CheckMark"
                                    Data="M 2 8 L 7 13 L 16 4"
                                    Stroke="$accentColor"
                                    StrokeThickness="2"
                                    Visibility="Collapsed"/>
                            </Border>
                            <ContentPresenter
                                Grid.Column="1"
                                VerticalAlignment="Center"
                                Content="{TemplateBinding Content}"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                                <Setter TargetName="CheckBoxBorder" Property="Background" Value="$accentColor"/>
                                <Setter TargetName="CheckBoxBorder" Property="BorderBrush" Value="$accentColor"/>
                                <Setter TargetName="CheckMark" Property="Stroke" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="CheckBoxBorder" Property="BorderBrush" Value="$accentColor"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Slider Button Style (must be defined before ModernSlider) -->
        <Style x:Key="SliderButtonStyle" TargetType="RepeatButton">
            <Setter Property="SnapsToDevicePixels" Value="true"/>
            <Setter Property="OverridesDefaultStyle" Value="true"/>
            <Setter Property="IsTabStop" Value="false"/>
            <Setter Property="Focusable" Value="false"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RepeatButton">
                        <Border Background="Transparent"/>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Modern Slider Style -->
        <Style x:Key="ModernSlider" TargetType="Slider">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Slider">
                        <Grid>
                            <Border
                                x:Name="TrackBackground"
                                Height="4"
                                Background="$borderColor"
                                CornerRadius="2"
                                VerticalAlignment="Center"/>
                            <Track x:Name="PART_Track">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="Slider.DecreaseLarge" Style="{StaticResource SliderButtonStyle}"/>
                                </Track.DecreaseRepeatButton>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="Slider.IncreaseLarge" Style="{StaticResource SliderButtonStyle}"/>
                                </Track.IncreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb>
                                        <Thumb.Template>
                                            <ControlTemplate>
                                                <Grid>
                                                    <Ellipse
                                                        x:Name="ThumbEllipse"
                                                        Width="16"
                                                        Height="16"
                                                        Fill="$accentColor"
                                                        Stroke="White"
                                                        StrokeThickness="2"/>
                                                </Grid>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="ThumbEllipse" Property="StrokeThickness" Value="3"/>
                                                    </Trigger>
                                                </ControlTemplate.Triggers>
                                            </ControlTemplate>
                                        </Thumb.Template>
                                    </Thumb>
                                </Track.Thumb>
                            </Track>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Opacity" Value="0.5"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- Modern Button Styles -->
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="$accentColor"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border
                            x:Name="ButtonBorder"
                            Background="{TemplateBinding Background}"
                            CornerRadius="4"
                            Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.9"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.8"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="$hoverBackground"/>
            <Setter Property="Foreground" Value="$textColor"/>
            <Setter Property="BorderBrush" Value="$borderColor"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border
                            x:Name="ButtonBorder"
                            Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            CornerRadius="4"
                            Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.8"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border Background="$backgroundColor" CornerRadius="8">
        <Border.Effect>
            <DropShadowEffect Color="Black" BlurRadius="20" ShadowDepth="0" Opacity="0.3"/>
        </Border.Effect>
        <Grid Margin="0">
            <Grid.RowDefinitions>
                <RowDefinition Height="40"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Custom Title Bar (Draggable) -->
            <Border
                x:Name="TitleBar"
                Grid.Row="0"
                Background="$cardBackground"
                BorderBrush="$borderColor"
                BorderThickness="0,0,0,1"
                CornerRadius="8,8,0,0"
                Cursor="SizeAll">
                <TextBlock
                    Text="Quality Analyzer Settings"
                    FontFamily="Segoe UI Variable, Segoe UI"
                    FontSize="13"
                    Foreground="$textColor"
                    VerticalAlignment="Center"
                    Margin="16,0"/>
            </Border>

            <!-- Main Content Card -->
            <Border
                Grid.Row="1"
                Margin="32,24,32,0"
                Background="$cardBackground"
                BorderBrush="$borderColor"
                BorderThickness="1"
                CornerRadius="8"
                Padding="24">

                <StackPanel>

                    <!-- Quality Metrics Selection -->
                    <TextBlock
                        Text="Quality Metrics"
                        FontFamily="Segoe UI Variable, Segoe UI"
                        FontSize="14"
                        FontWeight="SemiBold"
                        Foreground="$textColor"
                        Margin="0,0,0,12"/>

                    <TextBlock
                        Text="Select at least one metric to analyze video quality"
                        FontSize="11"
                        Foreground="$secondaryTextColor"
                        Margin="0,0,0,16"/>

                    <CheckBox
                        x:Name="VMAFCheckBox"
                        Content="VMAF - Most accurate (slowest, requires libvmaf)"
                        Style="{StaticResource ModernCheckBox}"
                        Margin="0,0,0,16"/>

                    <CheckBox
                        x:Name="SSIMCheckBox"
                        Content="SSIM - Structural similarity (moderate speed)"
                        Style="{StaticResource ModernCheckBox}"
                        Margin="0,0,0,16"/>

                    <CheckBox
                        x:Name="PSNRCheckBox"
                        Content="PSNR - Peak signal-to-noise ratio (fastest)"
                        Style="{StaticResource ModernCheckBox}"
                        Margin="0,0,0,24"/>

                    <!-- VMAF Subsample Slider (only shown when VMAF is selected) -->
                    <StackPanel x:Name="VMAFSubsamplePanel" Visibility="Collapsed">
                        <Grid Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock
                                Grid.Column="0"
                                Text="VMAF Subsample (n_subsample)"
                                FontFamily="Segoe UI Variable, Segoe UI"
                                FontSize="14"
                                FontWeight="SemiBold"
                                Foreground="$textColor"
                                VerticalAlignment="Center"/>
                            <TextBlock
                                x:Name="SubsampleValue"
                                Grid.Column="1"
                                Text="100"
                                FontFamily="Segoe UI Variable, Segoe UI"
                                FontSize="16"
                                FontWeight="Bold"
                                Foreground="$accentColor"
                                VerticalAlignment="Center"/>
                        </Grid>

                        <Slider
                            x:Name="SubsampleSlider"
                            Style="{StaticResource ModernSlider}"
                            Minimum="1"
                            Maximum="500"
                            Value="100"
                            TickFrequency="1"
                            IsSnapToTickEnabled="True"
                            Margin="0,0,0,8"/>

                        <Grid Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="1 (slowest)" FontSize="11" Foreground="$secondaryTextColor" HorizontalAlignment="Left"/>
                            <TextBlock Grid.Column="1" Text="100" FontSize="11" Foreground="$secondaryTextColor" HorizontalAlignment="Center"/>
                            <TextBlock Grid.Column="2" Text="500 (fastest)" FontSize="11" Foreground="$secondaryTextColor" HorizontalAlignment="Right"/>
                        </Grid>

                        <TextBlock
                            Text="Lower values = more accurate but slower analysis"
                            FontSize="11"
                            FontStyle="Italic"
                            Foreground="$secondaryTextColor"
                            Margin="0,0,0,20"/>
                    </StackPanel>

                    <!-- Info Box -->
                    <Border
                        Background="$infoBoxBg"
                        BorderBrush="$infoBoxBorder"
                        BorderThickness="1"
                        CornerRadius="4"
                        Padding="12">
                        <StackPanel>
                            <TextBlock
                                Text="Quality Assessment Priority"
                                FontSize="12"
                                FontWeight="SemiBold"
                                Foreground="$infoBoxText"/>
                            <TextBlock
                                Text="VMAF > SSIM > PSNR (based on selected metrics)"
                                FontSize="11"
                                Foreground="$infoBoxText"
                                Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>

                    <!-- Validation Message -->
                    <TextBlock
                        x:Name="ValidationMessage"
                        Text="Please select at least one metric"
                        FontSize="12"
                        Foreground="Red"
                        Margin="0,12,0,0"
                        Visibility="Collapsed"/>

                </StackPanel>
            </Border>

            <!-- Action Buttons -->
            <Grid Grid.Row="2" Margin="32,24,32,32">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="12"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <Button
                    x:Name="CancelButton"
                    Grid.Column="1"
                    Content="Cancel"
                    Style="{StaticResource SecondaryButton}"
                    Width="120"
                    Height="40"
                    FontSize="14"/>
                <Button
                    x:Name="StartButton"
                    Grid.Column="3"
                    Content="Start Analysis"
                    Style="{StaticResource PrimaryButton}"
                    Width="160"
                    Height="40"
                    FontSize="14"
                    FontWeight="SemiBold"/>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

    # Load XAML
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # Apply dark title bar
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WindowHelper {
    [DllImport("dwmapi.dll", PreserveSig = true)]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@

    $window.Add_SourceInitialized({
        $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
        $darkMode = if ($currentTheme -eq "Dark") { 1 } else { 0 }
        [WindowHelper]::DwmSetWindowAttribute($hwnd, 20, [ref]$darkMode, 4) | Out-Null
    })

    # Get controls
    $titleBar = $window.FindName("TitleBar")
    $vmafCheckBox = $window.FindName("VMAFCheckBox")
    $ssimCheckBox = $window.FindName("SSIMCheckBox")
    $psnrCheckBox = $window.FindName("PSNRCheckBox")
    $vmafSubsamplePanel = $window.FindName("VMAFSubsamplePanel")
    $subsampleSlider = $window.FindName("SubsampleSlider")
    $subsampleValue = $window.FindName("SubsampleValue")
    $validationMessage = $window.FindName("ValidationMessage")
    $startButton = $window.FindName("StartButton")
    $cancelButton = $window.FindName("CancelButton")

    # Make title bar draggable
    $titleBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    # Set default values
    $vmafCheckBox.IsChecked = $EnableVMAF
    $ssimCheckBox.IsChecked = $EnableSSIM
    $psnrCheckBox.IsChecked = $EnablePSNR
    $subsampleSlider.Value = $VMAF_Subsample
    $subsampleValue.Text = $VMAF_Subsample.ToString()

    # Update VMAF subsample panel visibility
    $UpdateVMAFPanelVisibility = {
        if ($vmafCheckBox.IsChecked) {
            $vmafSubsamplePanel.Visibility = [System.Windows.Visibility]::Visible
        } else {
            $vmafSubsamplePanel.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }

    # Apply initial state
    & $UpdateVMAFPanelVisibility

    # VMAF checkbox event
    $vmafCheckBox.Add_Checked({
        & $UpdateVMAFPanelVisibility
    })

    $vmafCheckBox.Add_Unchecked({
        & $UpdateVMAFPanelVisibility
    })

    # Subsample slider event
    $subsampleSlider.Add_ValueChanged({
        $value = [int]$subsampleSlider.Value
        $subsampleValue.Text = $value.ToString()
    })

    # Validation function
    $ValidateSelection = {
        $isValid = $vmafCheckBox.IsChecked -or $ssimCheckBox.IsChecked -or $psnrCheckBox.IsChecked
        if ($isValid) {
            $validationMessage.Visibility = [System.Windows.Visibility]::Collapsed
            $startButton.IsEnabled = $true
        } else {
            $validationMessage.Visibility = [System.Windows.Visibility]::Visible
            $startButton.IsEnabled = $false
        }
    }

    # Apply initial validation
    & $ValidateSelection

    # Add validation on checkbox changes
    $vmafCheckBox.Add_Checked({ & $ValidateSelection })
    $vmafCheckBox.Add_Unchecked({ & $ValidateSelection })
    $ssimCheckBox.Add_Checked({ & $ValidateSelection })
    $ssimCheckBox.Add_Unchecked({ & $ValidateSelection })
    $psnrCheckBox.Add_Checked({ & $ValidateSelection })
    $psnrCheckBox.Add_Unchecked({ & $ValidateSelection })

    # Button events
    $startButton.Add_Click({
        $window.DialogResult = $true
        $window.Close()
    })

    $cancelButton.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    # Show window and return results
    $result = $window.ShowDialog()

    if ($result -eq $true) {
        return @{
            EnableVMAF = $vmafCheckBox.IsChecked
            EnableSSIM = $ssimCheckBox.IsChecked
            EnablePSNR = $psnrCheckBox.IsChecked
            VMAF_Subsample = [int]$subsampleSlider.Value
            Cancelled = $false
        }
    } else {
        return @{
            Cancelled = $true
        }
    }
}
