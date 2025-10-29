# ============================================================================
# MODERN WINDOWS 11 UI FOR IMAGE CONVERSION
# ============================================================================
# This file contains the UI logic for the image to HEIC conversion tool
# Returns a hashtable with user-selected settings

function Show-ImageConversionUI {
    param(
        [string]$OutputFormat,
        [int]$DefaultQuality,
        [string]$ChromaSubsampling,
        [int]$BitDepth,
        [bool]$PreserveMetadata,
        [bool]$SkipExistingFiles,
        [int]$ParallelJobs
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
    Height="800"
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
                                <Border
                                    x:Name="DropDownBorder"
                                    Background="$cardBackground"
                                    BorderBrush="$borderColor"
                                    BorderThickness="1"
                                    CornerRadius="4"
                                    MinWidth="{TemplateBinding ActualWidth}"
                                    MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <ScrollViewer Margin="0" SnapsToDevicePixels="True">
                                        <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/>
                                    </ScrollViewer>
                                </Border>
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

        <!-- Modern ScrollBar Style -->
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Width" Value="6"/>
            <Setter Property="Margin" Value="8,0,0,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Grid>
                            <Border Background="{TemplateBinding Background}" CornerRadius="3" Width="6"/>
                            <Track x:Name="PART_Track" IsDirectionReversed="True" Width="6">
                                <Track.Thumb>
                                    <Thumb Width="6">
                                        <Thumb.Template>
                                            <ControlTemplate TargetType="Thumb">
                                                <Border
                                                    x:Name="ThumbBorder"
                                                    Background="$secondaryTextColor"
                                                    CornerRadius="3"
                                                    Width="6"
                                                    Opacity="0.3"/>
                                                <ControlTemplate.Triggers>
                                                    <Trigger Property="IsMouseOver" Value="True">
                                                        <Setter TargetName="ThumbBorder" Property="Opacity" Value="0.6"/>
                                                        <Setter TargetName="ThumbBorder" Property="Background" Value="$accentColor"/>
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

        <!-- CheckBox Style -->
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
                                x:Name="CheckBorder"
                                Grid.Column="0"
                                Width="20"
                                Height="20"
                                Background="$cardBackground"
                                BorderBrush="$borderColor"
                                BorderThickness="2"
                                CornerRadius="4">
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
                                Margin="8,0,0,0"
                                Content="{TemplateBinding Content}"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                                <Trigger Property="IsChecked" Value="True">
                                    <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                                    <Setter TargetName="CheckBorder" Property="Background" Value="$accentColor"/>
                                    <Setter TargetName="CheckBorder" Property="BorderBrush" Value="$accentColor"/>
                                    <Setter TargetName="CheckMark" Property="Stroke" Value="White"/>
                                </Trigger>
                                <Trigger Property="IsMouseOver" Value="True">
                                    <Setter TargetName="CheckBorder" Property="BorderBrush" Value="$accentColor"/>
                                </Trigger>
                            </ControlTemplate.Triggers>
                        </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Primary Button Style -->
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="$accentColor"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border
                            x:Name="Border"
                            Background="{TemplateBinding Background}"
                            BorderThickness="0"
                            CornerRadius="4"
                            Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Opacity" Value="0.9"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Border" Property="Opacity" Value="0.8"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Secondary Button Style -->
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="$textColor"/>
            <Setter Property="BorderBrush" Value="$borderColor"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border
                            x:Name="Border"
                            Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="1"
                            CornerRadius="4"
                            Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="$hoverBackground"/>
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
                    Text="Image to HEIC Conversion"
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

                        <!-- Output Format -->
                        <TextBlock
                            Text="Output Format"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="14"
                            FontWeight="SemiBold"
                            Foreground="$textColor"
                            Margin="0,0,0,8"/>
                        <ComboBox
                            x:Name="FormatCombo"
                            Style="{StaticResource ModernComboBox}"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="13"
                            Padding="12,10"
                            Margin="0,0,0,24">
                        <ComboBoxItem Content="HEIC (.heic)"/>
                        <ComboBoxItem Content="HEIF (.heif)"/>
                    </ComboBox>

                        <!-- Quality -->
                        <Grid Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock
                                Grid.Column="0"
                                Text="Quality"
                                FontFamily="Segoe UI Variable, Segoe UI"
                                FontSize="14"
                                FontWeight="SemiBold"
                                Foreground="$textColor"
                                VerticalAlignment="Center"/>
                            <TextBlock
                                x:Name="QualityValue"
                                Grid.Column="1"
                                Text="85%"
                                FontFamily="Segoe UI Variable, Segoe UI"
                                FontSize="16"
                                FontWeight="Bold"
                                Foreground="$accentColor"
                                VerticalAlignment="Center"/>
                        </Grid>
                        <Slider
                            x:Name="QualitySlider"
                            Style="{StaticResource ModernSlider}"
                            Minimum="1"
                            Maximum="100"
                            Value="85"
                            IsSnapToTickEnabled="True"
                            TickFrequency="1"
                            Margin="0,0,0,10"/>
                        <Grid Margin="0,0,0,24">
                            <TextBlock Text="Lowest" FontFamily="Segoe UI Variable, Segoe UI" Foreground="$secondaryTextColor" FontSize="11" HorizontalAlignment="Left"/>
                            <TextBlock Text="Balanced" FontFamily="Segoe UI Variable, Segoe UI" Foreground="$secondaryTextColor" FontSize="11" HorizontalAlignment="Center"/>
                            <TextBlock Text="Highest" FontFamily="Segoe UI Variable, Segoe UI" Foreground="$secondaryTextColor" FontSize="11" HorizontalAlignment="Right"/>
                        </Grid>

                        <!-- Chroma Subsampling -->
                        <TextBlock
                            Text="Chroma Subsampling"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="14"
                            FontWeight="SemiBold"
                            Foreground="$textColor"
                            Margin="0,0,0,8"/>
                        <ComboBox
                            x:Name="ChromaCombo"
                            Style="{StaticResource ModernComboBox}"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="13"
                            Padding="12,10"
                            Margin="0,0,0,24">
                        <ComboBoxItem Content="Same as source (recommended)"/>
                        <ComboBoxItem Content="4:2:0 (Most Compatible)"/>
                        <ComboBoxItem Content="4:2:2 (Better Color)"/>
                        <ComboBoxItem Content="4:4:4 (Best Quality)"/>
                    </ComboBox>

                        <!-- Bit Depth -->
                        <TextBlock
                            Text="Output Bit Depth"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="14"
                            FontWeight="SemiBold"
                            Foreground="$textColor"
                            Margin="0,0,0,8"/>
                        <ComboBox
                            x:Name="BitDepthCombo"
                            Style="{StaticResource ModernComboBox}"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="13"
                            Padding="12,10"
                            Margin="0,0,0,24">
                            <ComboBoxItem Content="Same as source (recommended)"/>
                            <ComboBoxItem Content="8-bit - Standard (smaller files, wider compatibility)"/>
                            <ComboBoxItem Content="10-bit - Enhanced (better gradients, HDR support)"/>
                        </ComboBox>

                        <!-- Parallel Jobs -->
                        <Grid Margin="0,0,0,12">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock
                                Grid.Column="0"
                                Text="Parallel Jobs"
                                FontFamily="Segoe UI Variable, Segoe UI"
                                FontSize="14"
                                FontWeight="SemiBold"
                                Foreground="$textColor"
                                VerticalAlignment="Center"/>
                            <TextBlock
                                x:Name="ParallelJobsValue"
                                Grid.Column="1"
                                Text="4"
                                FontFamily="Segoe UI Variable, Segoe UI"
                                FontSize="16"
                                FontWeight="Bold"
                                Foreground="$accentColor"
                                VerticalAlignment="Center"/>
                        </Grid>
                        <Slider
                            x:Name="ParallelJobsSlider"
                            Style="{StaticResource ModernSlider}"
                            Minimum="1"
                            Maximum="16"
                            Value="4"
                            IsSnapToTickEnabled="True"
                            TickFrequency="1"
                            Margin="0,0,0,10"/>
                        <Grid Margin="0,0,0,24">
                            <TextBlock Text="Single (1)" FontFamily="Segoe UI Variable, Segoe UI" Foreground="$secondaryTextColor" FontSize="11" HorizontalAlignment="Left"/>
                            <TextBlock Text="Balanced (4-8)" FontFamily="Segoe UI Variable, Segoe UI" Foreground="$secondaryTextColor" FontSize="11" HorizontalAlignment="Center"/>
                            <TextBlock Text="Maximum (16)" FontFamily="Segoe UI Variable, Segoe UI" Foreground="$secondaryTextColor" FontSize="11" HorizontalAlignment="Right"/>
                        </Grid>

                        <!-- Options -->
                        <TextBlock
                            Text="Options"
                            FontFamily="Segoe UI Variable, Segoe UI"
                            FontSize="14"
                            FontWeight="SemiBold"
                            Foreground="$textColor"
                            Margin="0,0,0,16"/>
                        <CheckBox
                            x:Name="PreserveMetadataCheck"
                            Style="{StaticResource ModernCheckBox}"
                            Content="Preserve EXIF metadata (camera info, GPS, date, etc.)"
                            Margin="0,0,0,16"/>
                        <CheckBox
                            x:Name="SkipExistingCheck"
                            Style="{StaticResource ModernCheckBox}"
                            Content="Skip existing output files"
                            Margin="0,0,0,24"/>

                        <!-- Info Box -->
                        <Border
                            Background="$infoBoxBg"
                            BorderBrush="$infoBoxBorder"
                            BorderThickness="1"
                            CornerRadius="6"
                            Padding="16"
                            Margin="0,0,0,0">
                            <TextBlock
                                TextWrapping="Wrap"
                                FontFamily="Segoe UI Variable, Segoe UI"
                                Foreground="$infoBoxText"
                                FontSize="12"
                                LineHeight="18">
                                <Run Text="Place your images in"/>
                                <Run Text="_input_files" FontWeight="SemiBold"/>
                                <Run Text="folder. Converted HEIC images will be saved to"/>
                                <Run Text="_output_files" FontWeight="SemiBold"/>
                                <Run Text="folder."/>
                            </TextBlock>
                        </Border>

                    </StackPanel>
                </ScrollViewer>
            </Border>

            <!-- Button Bar -->
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
                    FontFamily="Segoe UI Variable, Segoe UI"
                    Width="110"
                    Height="36"
                    FontSize="13"
                    Padding="20,8"/>
                <Button
                    x:Name="StartButton"
                    Grid.Column="3"
                    Content="Start Conversion"
                    Style="{StaticResource PrimaryButton}"
                    FontFamily="Segoe UI Variable, Segoe UI"
                    Width="150"
                    Height="36"
                    FontSize="13"
                    FontWeight="SemiBold"
                    Padding="20,8"/>
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
    $formatCombo = $window.FindName("FormatCombo")
    $qualitySlider = $window.FindName("QualitySlider")
    $qualityValue = $window.FindName("QualityValue")
    $chromaCombo = $window.FindName("ChromaCombo")
    $bitDepthCombo = $window.FindName("BitDepthCombo")
    $parallelJobsSlider = $window.FindName("ParallelJobsSlider")
    $parallelJobsValue = $window.FindName("ParallelJobsValue")
    $preserveMetadataCheck = $window.FindName("PreserveMetadataCheck")
    $skipExistingCheck = $window.FindName("SkipExistingCheck")
    $startButton = $window.FindName("StartButton")
    $cancelButton = $window.FindName("CancelButton")

    # Make title bar draggable
    $titleBar.Add_MouseLeftButtonDown({
        $window.DragMove()
    })

    # Set default values
    $formatCombo.SelectedIndex = if ($OutputFormat -eq "heif") { 1 } else { 0 }

    # Set quality slider to default
    $qualitySlider.Value = $DefaultQuality

    # Update quality label
    $updateQualityLabel = {
        $quality = [int]$qualitySlider.Value
        $qualityValue.Text = "$quality%"
    }
    $qualitySlider.Add_ValueChanged($updateQualityLabel)
    & $updateQualityLabel

    $chromaCombo.SelectedIndex = switch ($ChromaSubsampling) {
        "420" { 1 }
        "422" { 2 }
        "444" { 3 }
        default { 0 }  # source
    }

    # Default to "Same as source" (index 0)
    $bitDepthCombo.SelectedIndex = 0

    # Set parallel jobs slider to default
    $parallelJobsSlider.Value = $ParallelJobs

    # Update parallel jobs label
    $updateParallelJobsLabel = {
        $jobs = [int]$parallelJobsSlider.Value
        $parallelJobsValue.Text = "$jobs"
    }
    $parallelJobsSlider.Add_ValueChanged($updateParallelJobsLabel)
    & $updateParallelJobsLabel

    $preserveMetadataCheck.IsChecked = $PreserveMetadata
    $skipExistingCheck.IsChecked = $SkipExistingFiles

    # Button handlers
    $script:result = $null

    $startButton.Add_Click({
        $script:result = @{
            Start = $true
            OutputFormat = if ($formatCombo.SelectedIndex -eq 1) { "heif" } else { "heic" }
            Quality = [int]$qualitySlider.Value
            ChromaSubsampling = switch ($chromaCombo.SelectedIndex) {
                0 { "source" }  # Same as source
                1 { "420" }     # 4:2:0
                2 { "422" }     # 4:2:2
                3 { "444" }     # 4:4:4
                default { "source" }
            }
            BitDepth = switch ($bitDepthCombo.SelectedIndex) {
                0 { "source" }  # Same as source
                1 { 8 }         # 8-bit
                2 { 10 }        # 10-bit
                default { "source" }
            }
            ParallelJobs = [int]$parallelJobsSlider.Value
            PreserveMetadata = $preserveMetadataCheck.IsChecked
            SkipExistingFiles = $skipExistingCheck.IsChecked
        }
        $window.Close()
    })

    $cancelButton.Add_Click({
        $script:result = @{ Start = $false }
        $window.Close()
    })

    # Show window
    [void]$window.ShowDialog()

    return $script:result
}
