# ==============================================================================
# GROUP 6: Status
# ==============================================================================

# Check system and development environment status
[group('Just')]
status:
    @echo "=== Image Configuration ==="
    @echo "Project:  {{ image_name }}"
    @echo "Tag:      {{ default_tag }}"
    @echo ""
    @echo "=== Local Images (localhost/) ==="
    @${PODMAN} images --filter "reference=localhost/{{ image_name }}*" --format "table {{ '{{.Repository}}' }}\t{{ '{{.Tag}}' }}\t{{ '{{.ID}}' }}\t{{ '{{.CreatedSince}}' }}"
    @echo ""
    @echo "=== Tooling Versions ==="
    @echo "Just:    $(just --version | head -n1)"
    @echo "Podman:  $(${PODMAN} --version)"
    @echo ""
    @echo "=== BIB Engine ==="
    @echo "Image:   {{ bib_image }}"
    @echo ""
    @echo "=== G15 Status ==="
    @just g15-status

# Check hardware and system health status
[group('Just')]
g15-status:
    /usr/bin/g15-status
