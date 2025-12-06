import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/delivery_address.dart';
import '../services/address_validation_service.dart';
import '../services/geocoding_service.dart';
import '../widgets/autocomplete.dart';

class AddEditAddressDialog extends StatefulWidget {
  final DeliveryAddress? address;
  final String userId;
  final Function(DeliveryAddress) onSave;

  const AddEditAddressDialog({
    super.key,
    this.address,
    required this.userId,
    required this.onSave,
  });

  @override
  State<AddEditAddressDialog> createState() => _AddEditAddressDialogState();
}

class _AddEditAddressDialogState extends State<AddEditAddressDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _addressController;
  late TextEditingController _notesController;
  final _notesFocusNode = FocusNode(); // <-- NEW
  bool _isLoading = false;

  // Store place details when selected from autocomplete
  PlaceDetail? _selectedPlaceDetail;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: widget.address?.fullAddress ?? '');
    _notesController = TextEditingController(text: widget.address?.notes ?? '');
    _addressController.addListener(_onAddressTextChanged);
  }

  @override
  void dispose() {
    _addressController.removeListener(_onAddressTextChanged);
    _addressController.dispose();
    _notesController.dispose();
    _notesFocusNode.dispose(); // <-- NEW
    super.dispose();
  }

  void _onAddressTextChanged() {
    // If user manually edits the text field after selecting a place from autocomplete,
    // we should invalidate that selection and fall back to manual validation on submit.
    if (_selectedPlaceDetail != null && _addressController.text != _selectedPlaceDetail!.formattedAddress) {
      if (mounted) {
        setState(() {
          debugPrint('Address text changed, invalidating previous place selection.');
          _selectedPlaceDetail = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.address != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Address' : 'Add Address'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // -------- Address input (web-only autocomplete; falls back to text on non-web) --------
              if (kIsWeb) ...[
                AddressAutocompleteField(
                  apiKey: '', // Not used - server handles the API key
                  countryCode: null, // null = search globally
                  controller: _addressController,
                  onSelected: (place) {
                    debugPrint('Place selected: ${place.formattedAddress}');
                    _selectedPlaceDetail = place;
                    _addressController.text = place.formattedAddress;
                    // Now move focus to the notes field
                    _notesFocusNode.requestFocus();
                  },
                  onSubmitted: (_) { // <-- NEW
                    // When user presses Enter in address field, move to notes
                    _notesFocusNode.requestFocus();
                  },
                ),
                const SizedBox(height: 8),
                FormField<String>(
                  validator: (_) => _addressController.text.isEmpty ? 'Please enter an address' : null,
                  builder: (s) => s.hasError
                      ? Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            s.errorText!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ] else ...[
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Enter Address',
                    hintText: 'Street, City, State, ZIP Code',
                  ),
                  validator: (value) => value!.isEmpty ? 'Please enter an address' : null,
                  onFieldSubmitted: (_) { // <-- NEW
                    _notesFocusNode.requestFocus();
                  },
                ),
              ],
              const SizedBox(height: 16),
              // ---------------- Notes ----------------
              TextFormField(
                controller: _notesController,
                focusNode: _notesFocusNode, // <-- NEW
                decoration: const InputDecoration(labelText: 'Notes (Optional)'),
                onFieldSubmitted: (_) => _submit(), // <-- NEW
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // If address was selected from Places API autocomplete, use that data directly
      // This bypasses strict validation since Places API already validated the address
      debugPrint('Submitting address. Has place detail: ${_selectedPlaceDetail != null}');
      if (_selectedPlaceDetail != null) {
        debugPrint('Formatted address: ${_selectedPlaceDetail!.formattedAddress}');
        debugPrint('Components: ${_selectedPlaceDetail!.addressComponents}');
        debugPrint('Coordinates: (${_selectedPlaceDetail!.lat}, ${_selectedPlaceDetail!.lng})');
        
        // Verify coordinates match the address using reverse geocoding (non-blocking)
        // Don't wait for this - just log it for debugging
        GeocodingService.reverseGeocode(
          _selectedPlaceDetail!.lat,
          _selectedPlaceDetail!.lng,
        ).then((reverseGeocoded) {
          debugPrint('Reverse geocoded address: $reverseGeocoded');
          debugPrint('Original formatted address: ${_selectedPlaceDetail!.formattedAddress}');
          
          // If the reverse geocoded address is very different, log a warning
          if (reverseGeocoded != 'Unknown Location') {
            final originalLower = _selectedPlaceDetail!.formattedAddress.toLowerCase();
            final reverseLower = reverseGeocoded.toLowerCase();
            if (!originalLower.contains(reverseLower.split(',')[0].trim()) && 
                !reverseLower.contains(originalLower.split(',')[0].trim())) {
              debugPrint('⚠️ WARNING: Reverse geocoded address differs significantly from Places API address!');
              debugPrint('   Places API: ${_selectedPlaceDetail!.formattedAddress}');
              debugPrint('   Reverse geocoded: $reverseGeocoded');
              debugPrint('   Coordinates: (${_selectedPlaceDetail!.lat}, ${_selectedPlaceDetail!.lng})');
            }
          }
        }).catchError((e) {
          debugPrint('Could not verify coordinates: $e');
        });
        
        final components = _selectedPlaceDetail!.addressComponents;
        
        // For Places API results, we trust the data even if some components are missing
        // This handles establishments, landmarks, and other non-standard addresses
        if (components != null && components.isNotEmpty) {
          // Extract components with fallbacks
          // For establishments, the streetAddress might be the establishment name
          // Check if we have an actualStreet (the real street address) vs just the establishment name
          String streetAddress = components['streetAddress'] ?? 
                                 components['actualStreet'] ??
                                 components['street'] ?? 
                                 components['establishmentName'] ?? 
                                 '';
          
          // If streetAddress is the establishment name and we have actualStreet, use that
          // Otherwise, if streetAddress is empty, try to parse from formatted address
          if (streetAddress.isEmpty && _selectedPlaceDetail!.formattedAddress.isNotEmpty) {
            final parts = _selectedPlaceDetail!.formattedAddress.split(',').map((s) => s.trim()).toList();
            if (parts.isNotEmpty) {
              streetAddress = parts[0];
            }
          }
          
          // For establishments, if the streetAddress is just the name and we have actualStreet, 
          // combine them: "Science and Innovation Center, 1000 Hempstead Turnpike"
          if (components.containsKey('actualStreet') && 
              components['actualStreet']!.isNotEmpty &&
              streetAddress != components['actualStreet']) {
            // The streetAddress is likely the establishment name, combine with actual street
            streetAddress = '${streetAddress}, ${components['actualStreet']}';
          }
          
          String city = components['city'] ?? '';
          // If no city, try to extract from formatted address (usually second part)
          if (city.isEmpty && _selectedPlaceDetail!.formattedAddress.isNotEmpty) {
            final parts = _selectedPlaceDetail!.formattedAddress.split(',').map((s) => s.trim()).toList();
            if (parts.length >= 2) {
              city = parts[1];
            }
          }
          
          String state = components['state'] ?? '';
          String zipCode = components['zipCode'] ?? components['postalCode'] ?? '';
          
          // Extract state and zip from formatted address if missing
          if ((state.isEmpty || zipCode.isEmpty) && _selectedPlaceDetail!.formattedAddress.isNotEmpty) {
            final parts = _selectedPlaceDetail!.formattedAddress.split(',').map((s) => s.trim()).toList();
            if (parts.length >= 3) {
              final stateZip = parts[2].split(' ').where((s) => s.isNotEmpty).toList();
              if (stateZip.isNotEmpty && state.isEmpty) {
                state = stateZip[0];
              }
              if (stateZip.length >= 2 && zipCode.isEmpty) {
                zipCode = stateZip[1];
              } else if (stateZip.length == 1 && zipCode.isEmpty) {
                // Might be just zip code
                final zipMatch = RegExp(r'\d{5}(-\d{4})?').firstMatch(stateZip[0]);
                if (zipMatch != null) {
                  zipCode = zipMatch.group(0)!;
                }
              }
            }
          }
          
          final newAddress = DeliveryAddress(
            id: widget.address?.id,
            userId: widget.userId,
            streetAddress: streetAddress,
            city: city,
            state: state,
            zipCode: zipCode,
            latitude: _selectedPlaceDetail!.lat,
            longitude: _selectedPlaceDetail!.lng,
            notes: _notesController.text,
          );

          widget.onSave(newAddress);
          if (mounted) Navigator.of(context).pop();
          return;
        } else if (_selectedPlaceDetail!.formattedAddress.isNotEmpty) {
          // Fallback: Parse formatted address even if components are missing
          // This handles edge cases where Places API doesn't return components
          final formatted = _selectedPlaceDetail!.formattedAddress;
          // Remove "USA" or "United States" from the end if present
          final cleaned = formatted.replaceAll(RegExp(r',\s*(USA|United States)$', caseSensitive: false), '');
          final parts = cleaned.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          
          if (parts.length >= 2) {
            String streetAddress = parts[0];
            String city = parts.length >= 2 ? parts[1] : '';
            String state = '';
            String zipCode = '';
            
            if (parts.length >= 3) {
              final stateZipPart = parts[2];
              final stateZip = stateZipPart.split(' ').where((s) => s.isNotEmpty).toList();
              if (stateZip.isNotEmpty) {
                // Check if first part is a state abbreviation (2 letters) or full state name
                if (stateZip[0].length == 2 && RegExp(r'^[A-Z]{2}$').hasMatch(stateZip[0])) {
                  state = stateZip[0];
                  if (stateZip.length >= 2) {
                    zipCode = stateZip[1];
                  }
                } else {
                  // Might be full state name, try to extract zip
                  final zipMatch = RegExp(r'\d{5}(-\d{4})?').firstMatch(stateZipPart);
                  if (zipMatch != null) {
                    zipCode = zipMatch.group(0)!;
                    state = stateZipPart.replaceAll(zipCode, '').trim();
                  } else {
                    state = stateZipPart;
                  }
                }
              }
            }
            
            final newAddress = DeliveryAddress(
              id: widget.address?.id,
              userId: widget.userId,
              streetAddress: streetAddress,
              city: city,
              state: state,
              zipCode: zipCode,
              latitude: _selectedPlaceDetail!.lat,
              longitude: _selectedPlaceDetail!.lng,
              notes: _notesController.text,
            );

            widget.onSave(newAddress);
            if (mounted) Navigator.of(context).pop();
            return;
          }
        }
        // If we still can't parse, fall through to validation
      }

      // Fallback: For manually entered addresses, use Address Validation API
      final validationResult = await AddressValidationService.validateAddress(_addressController.text);
      final result = validationResult['result']?['address']?['postalAddress'];
      final verdict = validationResult['result']?['verdict'];

      if (result != null && verdict != null && verdict['addressComplete'] == true) {
        final newAddress = DeliveryAddress(
          id: widget.address?.id,
          userId: widget.userId,
          streetAddress: (result['addressLines'] != null && result['addressLines'].isNotEmpty)
              ? result['addressLines'][0]
              : '',
          city: result['locality'] ?? '',
          state: result['administrativeArea'] ?? '',
          zipCode: result['postalCode'] ?? '',
          notes: _notesController.text,
        );

        widget.onSave(newAddress);
        if (mounted) Navigator.of(context).pop();
      } else {
        String errorMessage = 'Invalid address. Please try again.';
        if (verdict != null) {
          final issues = <String>[];
          if (verdict['addressComplete'] != true) {
            issues.add("The address appears to be incomplete.");
          }
          if (verdict['hasUnconfirmedComponents'] == true) {
            issues.add("Some address components could not be confirmed.");
          }
          errorMessage = issues.isNotEmpty ? issues.join(' ') : errorMessage;
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage, style: const TextStyle(color: Colors.white)),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to validate address: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
