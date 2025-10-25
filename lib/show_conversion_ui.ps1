# ============================================================================
# MODERN WINDOWS 11 UI FOR VIDEO CONVERSION
# ============================================================================
# This file contains the UI logic for the video conversion tool
# Returns a hashtable with user-selected settings

function Show-ConversionUI {
    param(
        [string]$OutputCodec,
        [bool]$PreserveContainer,
        [bool]$PreserveAudio,
        [double]$BitrateMultiplier,
        [string]$OutputExtension,
        [string]$AudioCodec,
        [string]$DefaultAudioBitrate
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
    Height="700"
    WindowStartupLocation="CenterScreen"
    ResizeMode="NoResize"
    WindowStyle="None"
    AllowsTransparency="True"
    Background="Transparent">

    <Window.Resources>
        <!-- Modern ComboBox Style -->
        <Style x:Key="ModernComboBox" TargetType="ComboBox">
            <Setter Property="Background" Value="$cardBackground"/>
            <Setter Property="Foreground" Value="$textColor"/>
            <Setter Property="BorderBrush" Value="$borderColor"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton
                                x:Name="ToggleButton"
                                Grid.Column="0"
                                Focusable="False"
                                MinHeight="44"
                                IsChecked="{Binding Path=IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}"
                                ClickMode="Press">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border
                                            x:Name="Border"
                                            Background="$cardBackground"
                                            BorderBrush="$borderColor"
                                            BorderThickness="1"
                                            CornerRadius="4"
                                            MinHeight="44">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="32"/>
                                                </Grid.ColumnDefinitions>
                                                <Path
                                                    Grid.Column="1"
                                                    Data="M 0 0 L 4 4 L 8 0 Z"
                                                    Fill="$secondaryTextColor"
                                                    HorizontalAlignment="Center"
                                                    VerticalAlignment="Center"/>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="Border" Property="BorderBrush" Value="$accentColor"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter
                                x:Name="ContentSite"
                                IsHitTestVisible="False"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}"
                                Margin="12,0,32,0"
                                VerticalAlignment="Center"
                                HorizontalAlignment="Left"/>
                            <Popup
                                x:Name="Popup"
                                Placement="Bottom"
                                IsOpen="{TemplateBinding IsDropDownOpen}"
                                AllowsTransparency="True"
                                Focusable="False"
                                PopupAnimation="Slide">
                                <Grid
                                    x:Name="DropDown"
                                    SnapsToDevicePixels="True"
                                    MinWidth="{TemplateBinding ActualWidth}"
                                    MaxHeight="300">
                                    <Border
                                        x:Name="DropDownBorder"
                                        Background="$cardBackground"
                                        BorderBrush="$borderColor"
                                        BorderThickness="1"
                                        CornerRadius="4"
                                        Margin="0,4,0,0">
                                        <ScrollViewer Margin="4,6,4,6" SnapsToDevicePixels="True">
                                            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
                                        </ScrollViewer>
                                    </Border>
                                </Grid>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Setter Property="ItemContainerStyle">
                <Setter.Value>
                    <Style TargetType="ComboBoxItem">
                        <Setter Property="Background" Value="$cardBackground"/>
                        <Setter Property="Foreground" Value="$textColor"/>
                        <Setter Property="Padding" Value="12,8"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ComboBoxItem">
                                    <Border
                                        x:Name="ItemBorder"
                                        Background="{TemplateBinding Background}"
                                        Padding="{TemplateBinding Padding}"
                                        CornerRadius="4"
                                        Margin="2,1">
                                        <ContentPresenter/>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsHighlighted" Value="True">
                                            <Setter TargetName="ItemBorder" Property="Background" Value="$hoverBackground"/>
                                        </Trigger>
                                        <Trigger Property="IsSelected" Value="True">
                                            <Setter TargetName="ItemBorder" Property="Background" Value="$hoverBackground"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                    </Style>
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
        </Style>

        <!-- Modern ScrollBar Style -->
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Width" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid>
                            <Border Background="{TemplateBinding Background}" CornerRadius="6"/>
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.Thumb>
                                    <Thumb>
                                        <Thumb.Template>
                                            <ControlTemplate>
                                                <Border
                                                    x:Name="ThumbBorder"
                                                    Background="$secondaryTextColor"
                                                    CornerRadius="6"
                                                    Opacity="0.5"/>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="ThumbBorder" Property="Opacity" Value="0.7"/>
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
                    Text="Video Conversion Settings"
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

                <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel>

                        <!-- Video Codec -->
                        <TextBlock
                            Text="Video Codec"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="14"
                            FontWeight="SemiBold"
                            Foreground="$textColor"
                            Margin="0,0,0,8"/>
                        <ComboBox
                            x:Name="CodecCombo"
                            Style="{StaticResource ModernComboBox}"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="13"
                            Padding="12,10"
                            Margin="0,0,0,24">
                            <ComboBoxItem Content="HEVC (H.265) - Better compatibility"/>
                            <ComboBoxItem Content="AV1 - Best compression (RTX 40+ only)"/>
                        </ComboBox>

                        <!-- Container Format -->
                        <TextBlock
                            Text="Container Format"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="14"
                            FontWeight="SemiBold"
                            Foreground="$textColor"
                            Margin="0,0,0,8"/>
                        <ComboBox
                            x:Name="ContainerCombo"
                            Style="{StaticResource ModernComboBox}"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="13"
                            Padding="12,10"
                            Margin="0,0,0,24">
                            <ComboBoxItem Content="Preserve original"/>
                            <ComboBoxItem Content="Convert all to $OutputExtension"/>
                        </ComboBox>

                        <!-- Audio Encoding -->
                        <TextBlock
                            Text="Audio Encoding"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="14"
                            FontWeight="SemiBold"
                            Foreground="$textColor"
                            Margin="0,0,0,8"/>
                        <ComboBox
                            x:Name="AudioCombo"
                            Style="{StaticResource ModernComboBox}"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="13"
                            Padding="12,10"
                            Margin="0,0,0,24">
                            <ComboBoxItem Content="Copy original audio (fastest, keeps quality)"/>
                            <ComboBoxItem Content="Re-encode to $($AudioCodec.ToUpper()) @ $DefaultAudioBitrate"/>
                        </ComboBox>

                        <!-- Bitrate Multiplier -->
                        <Grid Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock
                                Grid.Column="0"
                                Text="Bitrate Multiplier"
                                FontFamily="Segoe UI Variable, Segoe UI"
                                FontSize="14"
                                FontWeight="SemiBold"
                                Foreground="$textColor"
                                VerticalAlignment="Center"/>
                            <TextBlock
                                x:Name="BitrateValue"
                                Grid.Column="1"
                                Text="1.0x"
                                FontFamily="Segoe UI Variable, Segoe UI"
                                FontSize="16"
                                FontWeight="Bold"
                                Foreground="$accentColor"
                                VerticalAlignment="Center"/>
                        </Grid>

                        <Slider
                            x:Name="BitrateSlider"
                            Style="{StaticResource ModernSlider}"
                            Minimum="1"
                            Maximum="30"
                            Value="10"
                            TickFrequency="1"
                            IsSnapToTickEnabled="True"
                            Margin="0,0,0,8"/>

                        <Grid Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="0.1x" FontSize="11" Foreground="$secondaryTextColor" HorizontalAlignment="Left"/>
                            <TextBlock Grid.Column="1" Text="1.0x" FontSize="11" Foreground="$secondaryTextColor" HorizontalAlignment="Center"/>
                            <TextBlock Grid.Column="2" Text="3.0x" FontSize="11" Foreground="$secondaryTextColor" HorizontalAlignment="Right"/>
                        </Grid>

                        <TextBlock
                            Text="Adjust encoding quality and file size"
                            FontSize="11"
                            FontStyle="Italic"
                            Foreground="$secondaryTextColor"
                            Margin="0,0,0,20"/>

                        <!-- Info Box -->
                        <Border
                            Background="$infoBoxBg"
                            BorderBrush="$infoBoxBorder"
                            BorderThickness="1"
                            CornerRadius="4"
                            Padding="12">
                            <StackPanel>
                                <TextBlock
                                    Text="Default values loaded from config.ps1"
                                    FontSize="12"
                                    FontWeight="SemiBold"
                                    Foreground="$infoBoxText"/>
                                <TextBlock
                                    Text="You can adjust these settings before starting conversion"
                                    FontSize="11"
                                    Foreground="$infoBoxText"
                                    Margin="0,4,0,0"/>
                            </StackPanel>
                        </Border>

                    </StackPanel>
                </ScrollViewer>
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
                    Content="Start Conversion"
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
    $codecCombo = $window.FindName("CodecCombo")
    $containerCombo = $window.FindName("ContainerCombo")
    $audioCombo = $window.FindName("AudioCombo")
    $bitrateSlider = $window.FindName("BitrateSlider")
    $bitrateValue = $window.FindName("BitrateValue")
    $startButton = $window.FindName("StartButton")
    $cancelButton = $window.FindName("CancelButton")

    # Make title bar draggable
    $titleBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    # Set default values
    $codecCombo.SelectedIndex = if ($OutputCodec -eq "HEVC") { 0 } else { 1 }
    $containerCombo.SelectedIndex = if ($PreserveContainer) { 0 } else { 1 }
    $audioCombo.SelectedIndex = if ($PreserveAudio) { 0 } else { 1 }
    $bitrateSlider.Value = [int]($BitrateMultiplier * 10)
    $bitrateValue.Text = "$($BitrateMultiplier.ToString('0.0'))x"

    # Slider event
    $bitrateSlider.Add_ValueChanged({
        $value = $bitrateSlider.Value / 10.0
        $bitrateValue.Text = "$($value.ToString('0.0'))x"
    })

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
            Codec = if ($codecCombo.SelectedIndex -eq 0) { "HEVC" } else { "AV1" }
            PreserveContainer = ($containerCombo.SelectedIndex -eq 0)
            PreserveAudio = ($audioCombo.SelectedIndex -eq 0)
            BitrateMultiplier = $bitrateSlider.Value / 10.0
            Cancelled = $false
        }
    } else {
        return @{
            Cancelled = $true
        }
    }
}
