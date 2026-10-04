#!/usr/bin/env bash

# Logging
LOG_FILE="${LOG_FILE:-/tmp/fleet-manager.log}"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
# scripts/dependency-graph-visualization.sh - Cross-repo dependency visualisatie
# Genereert een Mermaid grafiek van dependencies tussen repos
set -euo pipefail

source ~/.hermes/.env 2>/dev/null || true
source "$(dirname "$0")/../lib/config.sh"

echo "=== Dependency Graph Visualization ==="

# Configuratie
DEPENDENCY_GRAPH_FILE="${DEPENDENCY_GRAPH_FILE:-$HOME/.github_fleet_dependencies.json}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/.github_fleet_visualizations}"
mkdir -p "$OUTPUT_DIR"

# Functies
generate_mermaid_graph() {
  local graph_file="$1"
  local output_file="$2"
  
  if [ ! -f "$graph_file" ]; then
    echo "  ⚠️ Geen dependency grafiek gevonden: $graph_file"
    return 1
  fi
  
  # Genereer Mermaid flowchart
  local mermaid="graph TD
"
  
  # Voeg nodes toe
  jq -r 'keys[]' "$graph_file" 2>/dev/null | while read -r repo; do
    mermaid+="  ${repo}[${repo}]"
  done
  
  # Voeg edges toe
  jq -r 'to_entries[] | .key as $repo | .value[] | "\($repo) --> \(.)"' "$graph_file" 2>/dev/null | while read -r edge; do
    mermaid+="  $edge
"
  done
  
  # Schrijf naar file
  echo "$mermaid" > "$output_file"
  echo "  ✅ Mermaid grafiek opgeslagen: $output_file"
}

generate_html_visualization() {
  local graph_file="$1"
  local output_file="$2"
  
  if [ ! -f "$graph_file" ]; then
    echo "  ⚠️ Geen dependency grafiek gevonden: $graph_file"
    return 1
  fi
  
  # Genereer HTML met D3.js
  cat > "$output_file" << HTML
<!DOCTYPE html>
<html lang="nl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Dependency Graph</title>
  <script src="https://d3js.org/d3.v7.min.js"></script>
  <style>
    body { margin: 0; font-family: sans-serif; background: #0d1117; color: #c9d1d9; }
    #graph { width: 100vw; height: 100vh; }
    .node { fill: #58a6ff; stroke: #1f6feb; stroke-width: 2px; }
    .link { stroke: #30363d; stroke-opacity: 0.6; }
    .node-label { fill: #c9d1d9; font-size: 12px; }
  </style>
</head>
<body>
  <div id="graph"></div>
  <script>
    const data = $(cat "$graph_file");
    
    const width = window.innerWidth;
    const height = window.innerHeight;
    
    const svg = d3.select("#graph")
      .append("svg")
      .attr("width", width)
      .attr("height", height);
    
    const simulation = d3.forceSimulation()
      .force("link", d3.forceLink().id(d => d.id).distance(100))
      .force("charge", d3.forceManyBody().strength(-300))
      .force("center", d3.forceCenter(width / 2, height / 2));
    
    const nodes = Object.keys(data).map(id => ({ id }));
    const links = [];
    
    Object.entries(data).forEach(([source, targets]) => {
      targets.forEach(target => {
        links.push({ source, target });
      });
    });
    
    const link = svg.append("g")
      .selectAll("line")
      .data(links)
      .enter().append("line")
      .attr("class", "link");
    
    const node = svg.append("g")
      .selectAll("circle")
      .data(nodes)
      .enter().append("circle")
      .attr("class", "node")
      .attr("r", 8)
      .call(d3.drag()
        .on("start", dragstarted)
        .on("drag", dragged)
        .on("end", dragended));
    
    const label = svg.append("g")
      .selectAll("text")
      .data(nodes)
      .enter().append("text")
      .attr("class", "node-label")
      .attr("dx", 12)
      .attr("dy", 4)
      .text(d => d.id);
    
    simulation.nodes(nodes).on("tick", () => {
      link.attr("x1", d => d.source.x).attr("y1", d => d.source.y)
          .attr("x2", d => d.target.x).attr("y2", d => d.target.y);
      node.attr("cx", d => d.x).attr("cy", d => d.y);
      label.attr("x", d => d.x).attr("y", d => d.y);
    });
    
    simulation.force("link").links(links);
    
    function dragstarted(event, d) {
      if (!event.active) simulation.alphaTarget(0.3).restart();
      d.fx = d.x; d.fy = d.y;
    }
    function dragged(event, d) {
      d.fx = event.x; d.fy = event.y;
    }
    function dragended(event, d) {
      if (!event.active) simulation.alphaTarget(0);
      d.fx = null; d.fy = null;
    }
  </script>
</body>
</html>
HTML
  
  echo "  ✅ HTML visualisatie opgeslagen: $output_file"
}

# Hoofdlogica
echo "Dependency grafiek visualiseren..."

mermaid_file="$OUTPUT_DIR/dependency-graph.mmd"
html_file="$OUTPUT_DIR/dependency-graph.html"

generate_mermaid_graph "$DEPENDENCY_GRAPH_FILE" "$mermaid_file"
generate_html_visualization "$DEPENDENCY_GRAPH_FILE" "$html_file"

echo ""
echo "✅ Dependency graph visualization klaar"
