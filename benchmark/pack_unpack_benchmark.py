import struct
import time
from datetime import datetime

start_time = datetime.now()
#start_time = time.time()

for x in range(100000000): 
    result = struct.pack("ii",64,64)

end_time = datetime.now()
print('Duration: {}'.format(end_time - start_time))
#print("--- %s seconds ---" % (time.time() - start_time))
print(f"result: {result}")