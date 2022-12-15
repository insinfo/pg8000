#include <span>
#include <vector>
#include <cstdio>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include "time.h"
#include <map>

// #define my_sizeof(type) ((char *)(&type + 1) - (char *)(&type))

// to run: g++ pack_unpack_benchmark.cpp ; ./a.exe]
// gcc -Wall pack_unpack_benchmark.cpp -Ofast -lstdc++
// cl /O2 pack_unpack_benchmark.cpp
// typedef std::vector<uint8_t> byte_buffer;

// template <std::size_t N>
// void append_fixed_width(byte_buffer &buf, uintmax_t val)
// {
//     int shift = ((N - 1) * 8);
//     while (shift >= 0)
//     {
//         uintmax_t mask = (0xff << shift);
//         buf.push_back(uint8_t((val & mask) >> shift));
//         shift -= 8;
//     }
// }

// template <typename TagType, typename ValueType>
// void append_tlv(byte_buffer &buf, TagType t, ValueType val)
// {
//     append_fixed_width<sizeof(TagType)>(buf, uintmax_t(t));
//     append_fixed_width<sizeof(std::size_t)>(buf, uintmax_t(sizeof(ValueType)));
//     append_fixed_width<sizeof(ValueType)>(buf, uintmax_t(val));
// }

// template <typename IntType>
// void append_bytes(byte_buffer &buf, IntType val)
// {
//     append_fixed_width<sizeof(IntType)>(buf, uintmax_t(val));
// }
// template<int left = 0, int right = 0, typename T>
// constexpr auto slice(T&& container)
// {
//     if constexpr (right > 0)
//     {
//         return std::span(begin(std::forward<T>(container))+left, begin(std::forward<T>(container))+right);
//     }
//     else
//     {
//         return std::span(begin(std::forward<T>(container))+left, end(std::forward<T>(container))+right);
//     }
// }

// void debug_print(const char *str, byte_buffer vec)
// {
//     std::cout << str;
//     for (auto i : vec)
//         std::cout << i;

//     std::cout << "\r\n";
// }

void debug_print2(const char *str, std::vector<unsigned char> vec)
{
    std::cout << str;
    for (auto i : vec)
        std::cout << i;

    std::cout << "\r\n";
}

void debug_print(const char *str, char buf1[], int len)
{
    printf(str);
    for (int i = 0; i < len; i++)
    {
        printf("%c", buf1[i]);
    }
    printf("\r\n");
}

// byte_buffer h_pack(int intVal)
// {
//     int16_t val = (int16_t)intVal;
//     void *buf = &val;
//     byte_buffer result(static_cast<char *>(buf), static_cast<char *>(buf) + 2);
//     return result;
// }

// byte_buffer i_pack(int intVal)
// {
//     int32_t val = (int32_t)intVal;
//     void *buf = &val;
//     byte_buffer result(static_cast<char *>(buf), static_cast<char *>(buf) + 4);
//     return result;
// }

// byte_buffer c_pack(int intVal)
// {
//     uint8_t val = (uint8_t)intVal;
//     void *buf = &val;
//     byte_buffer result(static_cast<char *>(buf), static_cast<char *>(buf) + 4);
//     return result;
// }
#define STRUCT_ENDIAN_NOT_SET 0
#define STRUCT_ENDIAN_BIG 1
#define STRUCT_ENDIAN_LITTLE 2

static int myendian = STRUCT_ENDIAN_NOT_SET;

int struct_get_endian(void)
{
    int i = 0x00000001;
    if (((char *)&i)[0])
    {
        return STRUCT_ENDIAN_LITTLE;
    }
    else
    {
        return STRUCT_ENDIAN_BIG;
    }
}

static void struct_init(void)
{
    myendian = struct_get_endian();
}

static void pack_int16_t(unsigned char **bp, uint16_t val, int endian)
{
    if (endian == myendian)
    {
        *((*bp)++) = val;
        *((*bp)++) = val >> 8;
    }
    else
    {
        *((*bp)++) = val >> 8;
        *((*bp)++) = val;
    }
}

static void pack_int32_t(unsigned char **bp, uint32_t val, int endian)
{
    if (endian == myendian)
    {
        *((*bp)++) = val;
        *((*bp)++) = val >> 8;
        *((*bp)++) = val >> 16;
        *((*bp)++) = val >> 24;
    }
    else
    {
        *((*bp)++) = val >> 24;
        *((*bp)++) = val >> 16;
        *((*bp)++) = val >> 8;
        *((*bp)++) = val;
    }
}

static void pack_int64_t(unsigned char **bp, uint64_t val, int endian)
{
    if (endian == myendian)
    {
        *((*bp)++) = val;
        *((*bp)++) = val >> 8;
        *((*bp)++) = val >> 16;
        *((*bp)++) = val >> 24;
        *((*bp)++) = val >> 32;
        *((*bp)++) = val >> 40;
        *((*bp)++) = val >> 48;
        *((*bp)++) = val >> 56;
    }
    else
    {
        *((*bp)++) = val >> 56;
        *((*bp)++) = val >> 48;
        *((*bp)++) = val >> 40;
        *((*bp)++) = val >> 32;
        *((*bp)++) = val >> 24;
        *((*bp)++) = val >> 16;
        *((*bp)++) = val >> 8;
        *((*bp)++) = val;
    }
}

static int pack(void *b, const char *fmt, long long *values, int offset = 0)
{
    unsigned char *buf = (unsigned char *)b;

    int idx = 0;

    const char *p;
    unsigned char *bp;
    int ep = myendian;
    int endian;

    bp = buf + offset;
    auto bpp = &bp;

    if (STRUCT_ENDIAN_NOT_SET == myendian)
    {
        struct_init();
    }

    for (p = fmt; *p != '\0'; p++)
    {       
        auto value = values[idx];
        switch (*p)
        {
        case '=': /* native */
            ep = myendian;
            break;
        case '<': /* little-endian */
            endian = STRUCT_ENDIAN_LITTLE;
            ep = endian;
            break;
        case '>': /* big-endian */
            endian = STRUCT_ENDIAN_BIG;
            ep = endian;
            break;
        case '!': /* network (= big-endian) */
            endian = STRUCT_ENDIAN_BIG;
            ep = endian;
            break;
        case 'b':
            *bp++ = value;
            break;
        case 'c':
            *bp++ = value;
            break;
        case 'i':
            if (ep == STRUCT_ENDIAN_LITTLE)
            {
                *bp++ = value;
                *bp++ = value >> 8;
                *bp++ = value >> 16;
                *bp++ = value >> 24;
            }
            else
            {
                *bp++ = value >> 24;
                *bp++ = value >> 16;
                *bp++ = value >> 8;
                *bp++ = value;
            }
            break;
        case 'h':
            if (ep == STRUCT_ENDIAN_LITTLE)
            {
                *bp++ = value;
                *bp++ = value >> 8;
            }
            else
            {
                *bp++ = value >> 8;
                *bp++ = value;
            }
            break;
        case 'q':
            if (ep == STRUCT_ENDIAN_LITTLE)
            {
                *bp++ = value;
                *bp++ = value >> 8;
                *bp++ = value >> 16;
                *bp++ = value >> 24;
                *bp++ = value >> 32;
                *bp++ = value >> 40;
                *bp++ = value >> 48;
                *bp++ = value >> 56;
            }
            else
            {
                *bp++ = value >> 56;
                *bp++ = value >> 48;
                *bp++ = value >> 40;
                *bp++ = value >> 32;
                *bp++ = value >> 24;
                *bp++ = value >> 16;
                *bp++ = value >> 8;
                *bp++ = value;
            }
            break;
        }
        idx++;
    }

    return (bp - buf);
}

// std::string pack_uint32_be(uint32_t val)
// {
//     unsigned char packed[4];
//     packed[0] = val >> 24;
//     packed[1] = val >> 16 & 0xff;
//     packed[2] = val >> 8 & 0xff;
//     packed[3] = val & 0xff;
//     return std::string(packed, packed + 4);
// }
//gcc -Wall -O3  .\pack_unpack_benchmark.cpp -o pack_unpack_benchmark.exe -lstdc++
int main()
{

    time_t start, end;
    time(&start);
    // std::ios_base::sync_with_stdio(false);

    // char fmt[2] = {'i', 'i'};
    std::vector<unsigned char> myVector{};
    myVector.reserve(100000000 * 16);

    for (int i = 0; i < 100000000; i++) // 100000000
    {
        char bytes[BUFSIZ] = {'\0'};
        long long values[4] = {64, 65, 66, 67};
        pack(bytes, "iiii", values);

        for (int j = 0; j < 16; j++)
        {
            myVector.push_back(bytes[j]);
        }

        // byte_buffer bytes;
        // append_bytes(bytes, 64);
        // append_bytes(bytes, 64); // appends sizeof(int) bytes
        // //   append_bytes(bytes, 1ul); // appends sizeof(unsigned long) bytes
        // //   append_bytes(bytes, 'a'); // appends sizeof(int) bytes :p
        // //   append_bytes(bytes, char('a')); // appends 1 byte

        // result = bytes;
    }

    time(&end);
    auto v2 = std::vector<unsigned char>(myVector.begin(), myVector.begin() + 16);
    debug_print2("result: ", v2);

    double time_taken = double(end - start);
    std::cout << "pack time: " << std::fixed
              << time_taken << std::setprecision(5);
    std::cout << " sec " << std::endl;
    return 0;
}