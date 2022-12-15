import struct
import time
from datetime import datetime

start_time = datetime.now()


for x in range(100000000): 
    result = struct.pack("iiii",64,65,66,67)

end_time = datetime.now()

print(f"result: {result}")
print('{}'.format(end_time - start_time))