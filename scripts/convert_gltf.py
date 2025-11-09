#!/usr/bin/env python3
"""
Convert glTF files with interleaved buffers to separate buffers for each attribute.
This makes them compatible with zmesh which expects non-interleaved vertex data.
"""

import json
import struct
import sys
import base64
from pathlib import Path


def read_buffer_data(gltf_data, gltf_path):
    """Read buffer data from file or embedded base64."""
    buffers = []
    for buffer in gltf_data.get('buffers', []):
        if 'uri' in buffer:
            uri = buffer['uri']
            if uri.startswith('data:'):
                # Extract base64 data
                header, encoded = uri.split(',', 1)
                data = base64.b64decode(encoded)
            else:
                # Load from file
                buffer_path = gltf_path.parent / uri
                with open(buffer_path, 'rb') as f:
                    data = f.read()
        else:
            raise ValueError("Buffer without URI not supported")
        buffers.append(bytearray(data))
    return buffers


def get_accessor_data(gltf_data, buffers, accessor_idx):
    """Extract data for a specific accessor."""
    accessor = gltf_data['accessors'][accessor_idx]
    buffer_view = gltf_data['bufferViews'][accessor['bufferView']]
    
    buffer_idx = buffer_view['buffer']
    buffer_data = buffers[buffer_idx]
    
    # Get offsets
    buffer_offset = buffer_view.get('byteOffset', 0)
    accessor_offset = accessor.get('byteOffset', 0)
    total_offset = buffer_offset + accessor_offset
    
    # Get stride
    stride = buffer_view.get('byteStride', 0)
    
    # Component type sizes
    component_sizes = {
        5120: 1,  # BYTE
        5121: 1,  # UNSIGNED_BYTE
        5122: 2,  # SHORT
        5123: 2,  # UNSIGNED_SHORT
        5125: 4,  # UNSIGNED_INT
        5126: 4,  # FLOAT
    }
    
    # Type component counts
    type_counts = {
        'SCALAR': 1,
        'VEC2': 2,
        'VEC3': 3,
        'VEC4': 4,
        'MAT2': 4,
        'MAT3': 9,
        'MAT4': 16,
    }
    
    component_size = component_sizes[accessor['componentType']]
    component_count = type_counts[accessor['type']]
    element_size = component_size * component_count
    count = accessor['count']
    
    # If no stride, data is tightly packed
    if stride == 0:
        stride = element_size
    
    # Extract data
    extracted = bytearray()
    for i in range(count):
        offset = total_offset + i * stride
        extracted.extend(buffer_data[offset:offset + element_size])
    
    return extracted


def convert_gltf(input_path, output_path):
    """Convert glTF to non-interleaved format."""
    input_path = Path(input_path)
    output_path = Path(output_path)
    
    # Load glTF
    with open(input_path, 'r') as f:
        gltf_data = json.load(f)
    
    # Read buffer data
    buffers = read_buffer_data(gltf_data, input_path)
    
    # Create new buffers for each accessor
    new_buffers = []
    new_buffer_views = []
    new_accessors = []
    
    accessor_to_new_view = {}
    
    for accessor_idx, accessor in enumerate(gltf_data['accessors']):
        # Extract this accessor's data
        data = get_accessor_data(gltf_data, buffers, accessor_idx)
        
        # Create new buffer
        buffer_idx = len(new_buffers)
        new_buffers.append(data)
        
        # Create new buffer view
        view_idx = len(new_buffer_views)
        new_buffer_views.append({
            'buffer': buffer_idx,
            'byteOffset': 0,
            'byteLength': len(data),
        })
        
        # Create new accessor
        new_accessor = {
            'bufferView': view_idx,
            'byteOffset': 0,
            'componentType': accessor['componentType'],
            'count': accessor['count'],
            'type': accessor['type'],
        }
        
        # Copy min/max if present
        if 'min' in accessor:
            new_accessor['min'] = accessor['min']
        if 'max' in accessor:
            new_accessor['max'] = accessor['max']
        
        new_accessors.append(new_accessor)
        accessor_to_new_view[accessor_idx] = view_idx
    
    # Update glTF structure
    gltf_data['accessors'] = new_accessors
    gltf_data['bufferViews'] = new_buffer_views
    
    # Create single binary file with all buffers concatenated
    combined_buffer = bytearray()
    buffer_offsets = []
    
    for buf in new_buffers:
        buffer_offsets.append(len(combined_buffer))
        combined_buffer.extend(buf)
    
    # Update buffer views to point to combined buffer
    for i, view in enumerate(gltf_data['bufferViews']):
        original_buffer = view['buffer']
        view['buffer'] = 0
        view['byteOffset'] = buffer_offsets[original_buffer]
    
    # Update buffer reference
    bin_filename = output_path.stem + '0.bin'
    gltf_data['buffers'] = [{
        'byteLength': len(combined_buffer),
        'uri': bin_filename
    }]
    
    # Write binary file
    bin_path = output_path.parent / bin_filename
    with open(bin_path, 'wb') as f:
        f.write(combined_buffer)
    
    # Write glTF file
    with open(output_path, 'w') as f:
        json.dump(gltf_data, f, indent=2)
    
    print(f"Converted {input_path} -> {output_path}")
    print(f"  Original: {len(gltf_data.get('buffers', []))} buffers")
    print(f"  New: 1 combined buffer with {len(new_buffer_views)} separate views")
    print(f"  Binary data: {bin_path} ({len(combined_buffer)} bytes)")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Usage: convert_gltf.py <input.gltf> <output.gltf>")
        sys.exit(1)
    
    convert_gltf(sys.argv[1], sys.argv[2])
