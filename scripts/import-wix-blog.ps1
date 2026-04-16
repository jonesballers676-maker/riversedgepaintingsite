param(
  [string]$SourceBaseUrl = "https://www.robertjonesroofing.com",
  [int]$MaxPosts = 999,
  [switch]$SkipImages
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Decode-Html([string]$text) {
  if ([string]::IsNullOrWhiteSpace($text)) { return "" }
  return [System.Net.WebUtility]::HtmlDecode($text)
}

function Strip-Tags([string]$html) {
  if ([string]::IsNullOrWhiteSpace($html)) { return "" }
  $text = [regex]::Replace($html, "<[^>]+>", " ")
  $text = Decode-Html $text
  $text = [regex]::Replace($text, "\s+", " ").Trim()
  return $text
}

function Html-Encode([string]$text) {
  return [System.Net.WebUtility]::HtmlEncode($text)
}

function Slug-To-FileSafe([string]$slug) {
  $safe = $slug.ToLowerInvariant()
  $safe = [regex]::Replace($safe, "[^a-z0-9\-]", "-")
  $safe = [regex]::Replace($safe, "-{2,}", "-").Trim("-")
  if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "post" }
  return $safe
}

function Get-WebContent([string]$url) {
  $headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0 Safari/537.36"
    "Accept" = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
  }
  return (Invoke-WebRequest -Uri $url -Headers $headers).Content
}

function Extract-Title([string]$html, [string]$fallback) {
  $m = [regex]::Match($html, '(?is)<h1[^>]*data-hook="post-title"[^>]*>(.*?)</h1>')
  if ($m.Success) { return (Strip-Tags $m.Groups[1].Value) }
  $m = [regex]::Match($html, '(?is)<title[^>]*>(.*?)</title>')
  if ($m.Success) { return (Strip-Tags $m.Groups[1].Value) }
  return $fallback
}

function Extract-ReadingTime([string]$html) {
  $m = [regex]::Match($html, '(?is)data-hook="time-to-read"[^>]*>(.*?)</')
  if ($m.Success) { return (Strip-Tags $m.Groups[1].Value) }
  return ""
}

function Extract-ArticleSection([string]$html) {
  $m = [regex]::Match($html, '(?is)<section[^>]*data-hook="post-description"[^>]*>(.*?)</section>')
  if ($m.Success) { return $m.Groups[1].Value }
  return ""
}

function Extract-Blocks([string]$sectionHtml) {
  $blocks = New-Object System.Collections.Generic.List[object]
  if ([string]::IsNullOrWhiteSpace($sectionHtml)) { return $blocks }

  $matches = [regex]::Matches($sectionHtml, '(?is)<(h2|h3|p|li)\b[^>]*>(.*?)</\1>')
  $previous = ""
  foreach ($match in $matches) {
    $tag = $match.Groups[1].Value.ToLowerInvariant()
    $rawInner = $match.Groups[2].Value
    $text = Strip-Tags $rawInner
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    if ($text -eq $previous) { continue }
    $previous = $text
    $blocks.Add([PSCustomObject]@{
      Tag  = $tag
      Text = $text
    })
  }
  return $blocks
}

function Render-ArticleBody([System.Collections.Generic.List[object]]$blocks) {
  if ($blocks.Count -eq 0) {
    return "<p>Content was not available to import for this post yet.</p>"
  }

  $sb = New-Object System.Text.StringBuilder
  foreach ($b in $blocks) {
    $enc = Html-Encode $b.Text
    switch ($b.Tag) {
      "h2" { [void]$sb.AppendLine("          <h2 style=""font-family:'Barlow Condensed',sans-serif;letter-spacing:0.04em;text-transform:uppercase;color:var(--navy);font-size:1.5rem;margin:2rem 0 0.75rem;"">$enc</h2>") }
      "h3" { [void]$sb.AppendLine("          <h3 style=""font-family:'Barlow Condensed',sans-serif;letter-spacing:0.04em;text-transform:uppercase;color:var(--navy);font-size:1.2rem;margin:1.6rem 0 0.65rem;"">$enc</h3>") }
      "li" { [void]$sb.AppendLine("          <p style=""margin:0 0 1rem;color:var(--gray);line-height:1.8;"">&#8226; $enc</p>") }
      default { [void]$sb.AppendLine("          <p style=""margin:0 0 1rem;color:var(--gray);line-height:1.8;"">$enc</p>") }
    }
  }
  return $sb.ToString()
}

function Build-PostHtml(
  [string]$title,
  [string]$description,
  [string]$publishedDate,
  [string]$readingTime,
  [string]$imageSrc,
  [string]$articleBodyHtml
) {
@"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$(Html-Encode $title) | Robert Jones Roofing</title>
<meta name="description" content="$(Html-Encode $description)">
<link rel="preconnect" href="https://fonts.googleapis.com"><link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Barlow:ital,wght@0,300;0,400;0,500;0,600;1,400&family=Barlow+Condensed:wght@500;600;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/style.css">
</head>
<body><nav>
  <a href="/" class="nav-logo" aria-label="Robert Jones Roofing home">
    <img src="/images/logo.png" alt="" width="96" height="96" class="nav-logo-img" decoding="async">
    <div class="nav-logo-text">
      <span class="nav-logo-name">Robert Jones Roofing</span>
      <span class="nav-logo-sub">&amp; General Contracting</span>
    </div>
  </a>
  <button class="nav-hamburger" onclick="this.nextElementSibling.classList.toggle('open')" aria-label="Menu">
    <span></span><span></span><span></span>
  </button>
  <ul class="nav-links">
    <li><a href="/">Home</a></li>
    <li class="has-drop"><a href="#">Services &#9662;</a>
      <ul class="dropdown">
        <li><a href="/residential">Residential</a></li>
        <li><a href="/commercial">Commercial</a></li>
        <li><a href="/soft-washing">Soft Washing</a></li>
      </ul>
    </li>
    <li><a href="/our-work">Our Work</a></li>
    <li><a href="/faq">FAQ</a></li>
    <li><a href="/blog">Blog</a></li>
    <li class="has-drop"><a href="#">Our Team &#9662;</a>
      <ul class="dropdown">
        <li><a href="/christhreadgill">Chris Threadgill</a></li>
        <li><a href="/jasonwalton">Jason Walton</a></li>
        <li><a href="/jaketitus">Jake Titus</a></li>
      </ul>
    </li>
    <li><a href="/quotes" class="nav-cta">Free Quote</a></li>
  </ul>
</nav>
<div class="page-header">
  <div class="page-header-inner">
    <div class="page-eyebrow">Roofing Blog</div>
    <h1>$(Html-Encode $title)</h1>
    <p>Published $(Html-Encode $publishedDate)$(if($readingTime){" &#8226; " + (Html-Encode $readingTime)}else{""})</p>
  </div>
</div>
<section class="section section-alt">
  <div class="reveal" style="max-width:920px;margin:0 auto;">
    <p style="margin-bottom:1.25rem;"><a href="/blog" style="color:var(--blue-bright);text-decoration:none;font-weight:600;letter-spacing:0.04em;text-transform:uppercase;">&larr; Back to Blog</a></p>
    $(if($imageSrc){'<img src="' + (Html-Encode $imageSrc) + '" alt="' + (Html-Encode $title) + '" style="width:100%;max-height:520px;object-fit:cover;border-radius:10px;border:1px solid var(--light-gray);margin-bottom:1.5rem;" loading="eager" decoding="async">'}else{''})
    <article class="card" style="padding:2rem 2rem 1.25rem;">
$articleBodyHtml
    </article>
  </div>
</section>
<section class="cta-band">
  <h2>Need Help With Your Roof?</h2>
  <p>Call 321-403-5047 for a free estimate from our local Brevard County team.</p>
  <a href="tel:3214035047" class="cta-phone">321-403-5047</a>
  <a href="/quotes" class="btn btn-white btn-lg">Get Your Free Quote</a>
</section><div class="areas">
  <div class="areas-lbl">Proudly Serving All of Brevard County &amp; Beyond</div>
  <div class="areas-tags">
    <span class="area-chip">Titusville</span><span class="area-chip">Merritt Island</span>
    <span class="area-chip">Cocoa</span><a class="area-chip" href="/roofing-in-viera">Viera</a>
    <span class="area-chip">Melbourne</span><span class="area-chip">Palm Bay</span>
    <span class="area-chip">Mims</span><span class="area-chip">New Smyrna Beach</span>
    <span class="area-chip">Edgewater</span><a class="area-chip" href="/roofing-in-orlando-fl">Orlando</a>
    <a class="area-chip" href="/roofing-in-port-orange">Port Orange</a>
  </div>
</div><footer>
  <div class="footer-brand">
    <span class="footer-name">Robert Jones Roofing</span>
    <span class="footer-sub">&amp; General Contracting LLC</span>
    <div class="footer-tag">Titusville, FL &nbsp;&middot;&nbsp; Licensed &amp; Insured</div>
  </div>
  <div class="footer-col">
    <h4>Services</h4>
    <ul>
      <li><a href="/residential">Residential Roofing</a></li>
      <li><a href="/commercial">Commercial Roofing</a></li>
      <li><a href="/soft-washing">Soft Washing</a></li>
      <li><a href="/quotes">Free Estimate</a></li>
      <li><a href="/our-work">Our Work</a></li>
    </ul>
  </div>
  <div class="footer-col">
    <h4>Company</h4>
    <ul>
      <li><a href="/faq">FAQ</a></li>
      <li><a href="/blog">Blog</a></li>
      <li><a href="/christhreadgill">Chris Threadgill</a></li>
      <li><a href="/jasonwalton">Jason Walton</a></li>
      <li><a href="/jaketitus">Jake Titus</a></li>
    </ul>
  </div>
  <div class="footer-col">
    <h4>Service Areas</h4>
    <ul>
      <li><a href="/roofing-in-titusville">Titusville, FL</a></li>
      <li><a href="/roofing-in-merritt-island">Merritt Island, FL</a></li>
      <li><a href="/roofing-in-cocoa">Cocoa, FL</a></li>
      <li><a href="/roofing-in-viera">Viera, FL</a></li>
      <li><a href="/brevardcountyroofers">Brevard County, FL</a></li>
      <li><a href="/roofing-in-melbourne">Melbourne, FL</a></li>
      <li><a href="/roofing-in-palm-bay">Palm Bay, FL</a></li>
      <li><a href="/roofing-in-orlando-fl">Orlando, FL</a></li>
      <li><a href="/roofing-in-port-orange">Port Orange, FL</a></li>
    </ul>
  </div>
  <div class="footer-col">
    <div class="footer-info">
      <a href="tel:3214035047">321-403-5047</a><br>
      <a href="mailto:Info@robertjonesroofing.com">Info@robertjonesroofing.com</a><br>
      <a href="https://www.robertjonesroofing.com">www.robertjonesroofing.com</a><br>
      Mon-Fri: 9:00 AM - 5:00 PM
      <div class="footer-copy">&copy; 2025 Robert Jones Roofing &amp; General Contracting LLC. All rights reserved.</div>
    </div>
  </div>
</footer>
<script>
  const els = document.querySelectorAll('.reveal');
  const io = new IntersectionObserver(e => e.forEach(x => x.isIntersecting && x.target.classList.add('in')), {threshold:0});
  els.forEach(el => io.observe(el));
  document.querySelectorAll('.faq-q').forEach(btn => btn.addEventListener('click', () => btn.parentElement.classList.toggle('open')));
</script>
</body></html>
"@
}

function Build-BlogCardsHtml([array]$posts) {
  $cardBuilder = New-Object System.Text.StringBuilder
  foreach ($post in $posts) {
    $titleEnc = Html-Encode $post.Title
    $dateEnc = Html-Encode $post.PublishedLabel
    $excerptEnc = Html-Encode $post.Excerpt
    $hrefEnc = Html-Encode ("/$($post.RelativeHref)")
    $imgSrc = if ($post.ImageRel) { Html-Encode ("/$($post.ImageRel)") } else { "" }
    [void]$cardBuilder.AppendLine("    <div class=""card"" style=""display:flex;flex-direction:column;"">")
    if ($imgSrc) {
      [void]$cardBuilder.AppendLine("      <img src=""$imgSrc"" alt=""$titleEnc"" style=""width:calc(100% + 4.5rem);max-width:none;height:180px;border-radius:0;margin:-2.25rem -2.25rem 1.5rem;object-fit:cover;object-position:center;display:block;background:var(--navy);border-bottom:1px solid var(--light-gray);"" loading=""lazy"" decoding=""async"">")
    } else {
      [void]$cardBuilder.AppendLine("      <div style=""width:calc(100% + 4.5rem);max-width:none;background:var(--navy);height:180px;border-radius:0;margin:-2.25rem -2.25rem 1.5rem;box-sizing:border-box;display:flex;align-items:center;justify-content:center;border-bottom:1px solid var(--light-gray);""><svg width=""48"" height=""48"" viewBox=""0 0 24 24"" fill=""none"" stroke=""rgba(41,121,255,0.5)"" stroke-width=""1.5""><path d=""M13 10V3L4 14h7v7l9-11h-7z""/></svg></div>")
    }
    [void]$cardBuilder.AppendLine("      <div style=""font-size:0.72rem;font-weight:700;letter-spacing:0.12em;text-transform:uppercase;color:var(--blue-bright);margin-bottom:0.5rem;"">$dateEnc</div>")
    [void]$cardBuilder.AppendLine("      <h3 style=""font-size:1.1rem;margin-bottom:0.6rem;""><a href=""$hrefEnc"" style=""color:inherit;text-decoration:none;"">$titleEnc</a></h3>")
    [void]$cardBuilder.AppendLine("      <p style=""flex:1;"">$excerptEnc</p>")
    [void]$cardBuilder.AppendLine("      <a href=""$hrefEnc"" style=""display:inline-block;margin-top:1.25rem;font-size:0.82rem;font-weight:600;color:var(--blue-bright);text-decoration:none;letter-spacing:0.06em;text-transform:uppercase;"">Read Article -&gt;</a>")
    [void]$cardBuilder.AppendLine("    </div>")
  }

  return @"
<section class="section section-alt blog-list">
  <div class="reveal" style="margin-bottom:2rem;">
    <div class="eyebrow">Latest Posts</div>
    <h2 class="sec-title">Roofing Insights &amp; Homeowner Guides</h2>
    <p class="sec-sub">Imported from your original blog so homeowners can keep finding your helpful roofing content.</p>
  </div>
  <div class="card-grid card-grid-3">
$($cardBuilder.ToString().TrimEnd())
  </div>
</section>
"@
}

function Update-BlogListing([array]$posts, [string]$blogHtmlPath) {
  $blogHtml = [IO.File]::ReadAllText($blogHtmlPath)
  $replacementSection = Build-BlogCardsHtml $posts
  $updated = [regex]::Replace($blogHtml, '(?is)<section class="section section-alt[^"]*">.*?</section>', [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacementSection }, 1)
  [IO.File]::WriteAllText($blogHtmlPath, $updated, [System.Text.UTF8Encoding]::new($false))
}

function Update-Sitemap([array]$posts, [string]$sitemapPath) {
  [xml]$sitemap = Get-Content -Path $sitemapPath -Raw
  $ns = New-Object System.Xml.XmlNamespaceManager($sitemap.NameTable)
  $ns.AddNamespace("sm", "http://www.sitemaps.org/schemas/sitemap/0.9")

  $existing = @{}
  foreach ($loc in $sitemap.SelectNodes("//sm:url/sm:loc", $ns)) {
    $existing[$loc.InnerText] = $true
  }

  foreach ($post in $posts) {
    $url = "https://www.robertjonesroofing.com/$($post.RelativeHref)"
    if ($existing.ContainsKey($url)) { continue }
    $urlNode = $sitemap.CreateElement("url", "http://www.sitemaps.org/schemas/sitemap/0.9")
    $locNode = $sitemap.CreateElement("loc", "http://www.sitemaps.org/schemas/sitemap/0.9")
    $locNode.InnerText = $url
    [void]$urlNode.AppendChild($locNode)
    [void]$sitemap.urlset.AppendChild($urlNode)
    $existing[$url] = $true
  }

  $settings = New-Object System.Xml.XmlWriterSettings
  $settings.Indent = $true
  $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
  $writer = [System.Xml.XmlWriter]::Create($sitemapPath, $settings)
  $sitemap.Save($writer)
  $writer.Close()
}

$root = Split-Path -Parent $PSScriptRoot
$blogDir = Join-Path $root "blog"
$blogImageDir = Join-Path $root "images/blog"
$blogListingPath = Join-Path $root "blog.html"
$sitemapPath = Join-Path $root "sitemap.xml"
$reportPath = Join-Path $root "blog-import-report.json"

[IO.Directory]::CreateDirectory($blogDir) | Out-Null
[IO.Directory]::CreateDirectory($blogImageDir) | Out-Null

$sitemapUrl = "$SourceBaseUrl/blog-posts-sitemap.xml"
Write-Host "Fetching sitemap: $sitemapUrl"
[xml]$sourceSitemap = Get-WebContent $sitemapUrl

$smNs = New-Object System.Xml.XmlNamespaceManager($sourceSitemap.NameTable)
$smNs.AddNamespace("sm", "http://www.sitemaps.org/schemas/sitemap/0.9")
$smNs.AddNamespace("img", "http://www.google.com/schemas/sitemap-image/1.1")
$urlNodes = $sourceSitemap.SelectNodes("//sm:url", $smNs)

$toImport = @()
foreach ($node in $urlNodes) {
  if ($toImport.Count -ge $MaxPosts) { break }
  $loc = $node.SelectSingleNode("sm:loc", $smNs).InnerText
  if (-not $loc.Contains("/post/")) { continue }
  $lastmod = ""
  $lmNode = $node.SelectSingleNode("sm:lastmod", $smNs)
  if ($lmNode) { $lastmod = $lmNode.InnerText }
  $imgNode = $node.SelectSingleNode("img:image/img:loc", $smNs)
  $img = if ($imgNode) { $imgNode.InnerText } else { "" }
  $toImport += [PSCustomObject]@{
    Url      = $loc
    Lastmod  = $lastmod
    ImageUrl = $img
  }
}

Write-Host ("Found {0} blog post URLs." -f $toImport.Count)

$imported = New-Object System.Collections.Generic.List[object]
$counter = 0
foreach ($item in $toImport) {
  $counter++
  Write-Host ("[{0}/{1}] Importing {2}" -f $counter, $toImport.Count, $item.Url)

  try {
    $slug = ($item.Url -replace '^https?://[^/]+/post/', '').Trim('/')
    $fileSlug = Slug-To-FileSafe $slug
    $postHtml = Get-WebContent $item.Url

    $title = Extract-Title -html $postHtml -fallback $fileSlug
    $readingTime = Extract-ReadingTime $postHtml
    $section = Extract-ArticleSection $postHtml
    $blocks = Extract-Blocks $section
    $articleHtml = Render-ArticleBody $blocks

    $firstParagraph = ""
    foreach ($b in $blocks) {
      if ($b.Tag -eq "p" -and -not [string]::IsNullOrWhiteSpace($b.Text)) { $firstParagraph = $b.Text; break }
    }
    if ([string]::IsNullOrWhiteSpace($firstParagraph)) { $firstParagraph = "Helpful roofing advice from the Robert Jones Roofing team." }
    $excerpt = $firstParagraph
    if ($excerpt.Length -gt 180) { $excerpt = $excerpt.Substring(0,177).Trim() + "..." }

    $published = $item.Lastmod
    $publishedLabel = $item.Lastmod
    if ($item.Lastmod) {
      try {
        $dt = [datetime]::Parse($item.Lastmod)
        $published = $dt.ToString("yyyy-MM-dd")
        $publishedLabel = $dt.ToString("MMM d, yyyy")
      } catch {}
    }

    $imageRel = ""
    if (-not $SkipImages -and -not [string]::IsNullOrWhiteSpace($item.ImageUrl)) {
      try {
        $imgClean = ($item.ImageUrl -split '\?')[0]
        $ext = [IO.Path]::GetExtension($imgClean)
        if ([string]::IsNullOrWhiteSpace($ext)) { $ext = ".jpg" }
        $localImageName = "$fileSlug$ext"
        $localImagePath = Join-Path $blogImageDir $localImageName
        Invoke-WebRequest -Uri $item.ImageUrl -OutFile $localImagePath -Headers @{ "User-Agent" = "Mozilla/5.0" }
        $imageRel = "images/blog/$localImageName"
      } catch {
        Write-Warning ("  Image download failed: {0}" -f $item.ImageUrl)
      }
    }

    # On-disk files keep .html; public URLs stay extensionless via .htaccess
    $postOutputPath = Join-Path $blogDir "$fileSlug.html"
    $postRelativeHref = "post/$fileSlug"
    $description = $excerpt
    $heroImageSrc = if ($imageRel) { "/$imageRel" } else { "" }
    $renderedPost = Build-PostHtml -title $title -description $description -publishedDate $publishedLabel -readingTime $readingTime -imageSrc $heroImageSrc -articleBodyHtml $articleHtml
    [IO.File]::WriteAllText($postOutputPath, $renderedPost, [System.Text.UTF8Encoding]::new($false))

    $imported.Add([PSCustomObject]@{
      Title         = $title
      Slug          = $fileSlug
      RelativeHref  = $postRelativeHref
      Excerpt       = $excerpt
      Published     = $published
      PublishedLabel= $publishedLabel
      ImageRel      = $imageRel
      SourceUrl     = $item.Url
    }) | Out-Null
  }
  catch {
    Write-Warning ("Failed to import {0}: {1}" -f $item.Url, $_.Exception.Message)
  }
}

$ordered = $imported | Sort-Object -Property Published -Descending
Update-BlogListing -posts $ordered -blogHtmlPath $blogListingPath
Update-Sitemap -posts $ordered -sitemapPath $sitemapPath

$report = [PSCustomObject]@{
  ImportedCount = $ordered.Count
  GeneratedAt   = (Get-Date).ToString("s")
  SourceBaseUrl = $SourceBaseUrl
  Posts         = $ordered
}
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding UTF8

Write-Host ("Completed import. Generated {0} posts." -f $ordered.Count)
Write-Host ("Blog posts folder: {0}" -f $blogDir)
Write-Host ("Import report: {0}" -f $reportPath)
