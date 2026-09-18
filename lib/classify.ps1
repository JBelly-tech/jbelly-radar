# lib/classify.ps1 — deterministic technology tagging.
#
# config/taxonomy.json declares technologies as keyword lists. An item is tagged
# with every technology whose keywords appear (whole-word, case-insensitive) in
# its title, summary or source tags, ranked by how many distinct keywords hit.
# No model: the same item always gets the same tags, which is what makes the
# "filter by technology" chips and the relevance score trustworthy.

function Get-TaxonomyMatchers {
    param($Taxonomy)
    $matchers = New-Object System.Collections.Generic.List[object]
    foreach ($tech in $Taxonomy.technologies) {
        $parts = @()
        foreach ($k in @($tech.keywords)) {
            $w = "$k".Trim().ToLowerInvariant()
            if (-not $w) { continue }
            # Keywords are plain words or phrases; escape so "c++" or "node.js" stay literal.
            $parts += [regex]::Escape($w).Replace('\ ', '[\s-]+')
        }
        if ($parts.Count -eq 0) { continue }
        # Word boundaries on both sides, but a keyword may end in a non-word
        # character (c++, .net) — use lookarounds instead of \b so those still match.
        $pattern = '(?<![\w])(' + ($parts -join '|') + ')(?![\w])'
        $matchers.Add([pscustomobject]@{
            tag   = $tech.tag
            # scope "title": a word that is honest in a headline but appears in every
            # abstract ("benchmark", "gpu") is only tested against the title.
            scope = "$(Get-Prop $tech 'scope' 'all')"
            regex = New-Object System.Text.RegularExpressions.Regex($pattern, ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [System.Text.RegularExpressions.RegexOptions]::CultureInvariant))
        })
    }
    return $matchers
}

function Set-RadarTech {
    param($Items, $Taxonomy, [int]$MaxTags = 5)
    if ($null -eq $Taxonomy -or $null -eq $Taxonomy.technologies) {
        foreach ($it in $Items) { $it | Add-Member -NotePropertyName 'tech' -NotePropertyValue @() -Force }
        return
    }
    $matchers = Get-TaxonomyMatchers -Taxonomy $Taxonomy
    # GitHub topics are already tags; when a topic equals a taxonomy tag it is a
    # direct hit that outranks a keyword found in prose.
    $tagSet = @{}
    foreach ($tech in $Taxonomy.technologies) { $tagSet[$tech.tag.ToLowerInvariant()] = $true }

    foreach ($it in $Items) {
        $hay = (("$($it.title) $($it.summary) " + (@($it.tags) -join ' ')).ToLowerInvariant())
        $titleHay = ("$($it.title) " + (@($it.tags) -join ' ')).ToLowerInvariant()
        $scores = @{}
        foreach ($m in $matchers) {
            $text = $hay
            if ($m.scope -eq 'title') { $text = $titleHay }
            $hits = $m.regex.Matches($text)
            if ($hits.Count -eq 0) { continue }
            $distinct = @{}
            foreach ($h in $hits) { $distinct[$h.Value.ToLowerInvariant()] = $true }
            $scores[$m.tag] = $distinct.Count
        }
        foreach ($t in @($it.tags)) {
            $key = "$t".ToLowerInvariant()
            if ($tagSet.ContainsKey($key)) { $scores[$key] = [int](Get-Prop ([pscustomobject]$scores) $key 0) + 3 }
        }
        $tech = @($scores.GetEnumerator() | Sort-Object -Property @{ Expression = { $_.Value }; Descending = $true }, @{ Expression = { $_.Key } } | Select-Object -First $MaxTags | ForEach-Object { $_.Key })
        $it | Add-Member -NotePropertyName 'tech' -NotePropertyValue $tech -Force
    }
}
