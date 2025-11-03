# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- Multiple output formats (HTML, JSON, Markdown)
- Istio service mesh visibility
- Smart configuration warnings
- Demo cluster setup script
- Cross-platform support (Mac M1/M2/M3, Linux, Windows WSL2)

### Changed
- Renamed from aks-discover-v2.sh to k8s-cluster-discovery.sh
- Improved HTML report styling
- Better error handling

## [2.0.0] - 2025-10-31

### Added
- HTML report generation with visual dashboard
- JSON output for automation
- Markdown output for documentation
- Istio Gateway and VirtualService detection
- HPAs and PDBs tracking
- Multi-format support
- Universal Kubernetes compatibility

### Changed
- Complete rewrite for better performance
- Vendor-agnostic naming
- Improved data collection logic

### Fixed
- Edge cases with empty namespaces
- Context handling for minikube profiles

## [1.0.0] - 2025-01-15

### Added
- Initial release
- Basic cluster discovery
- Text-based output