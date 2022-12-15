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

// template <typename IntType> std::string
void pack(void *b, const char *fmt, long long *values)
{
    unsigned char *buf = (unsigned char *)b;
    const char *p;
    auto bp = &buf;
    int idx = 0;
    for (p = fmt; *p != '\0'; p++)
    {
        auto f = *p;
        auto value = values[idx];
        if (f == 'c')
        {
            *buf++ = value;
        }
        else if (f == 'i')
        {

            *((*bp)++) = value >> 24;
            *((*bp)++) = value >> 16;
            *((*bp)++) = value >> 8;
            *((*bp)++) = value;
        }
        else if (f == 'h')
        {
            *((*bp)++) = value >> 8;
            *((*bp)++) = value;
        }
        else if (f == 'q')
        {
            *((*bp)++) = value >> 56;
            *((*bp)++) = value >> 48;
            *((*bp)++) = value >> 40;
            *((*bp)++) = value >> 32;
            *((*bp)++) = value >> 24;
            *((*bp)++) = value >> 16;
            *((*bp)++) = value >> 8;
            *((*bp)++) = value;
        }

        idx++;
    }
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

int main()
{

    time_t start, end;
    time(&start);
    // std::ios_base::sync_with_stdio(false);

    // char fmt[2] = {'i', 'i'};
    std::vector<unsigned char> myVector{};
    myVector.reserve(100000000 * 16);
    // int val = 64;
    for (int i = 0; i < 100000000; i++) // 100000000
    {
        char result[BUFSIZ] = {
            '\0',
        };
        long long values[4] = {64, 65, 66, 67};
        pack(result, "iiii", values);      

        for (int j = 0; j < 16; j++)
        {
            myVector.push_back(result[j]);
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
    auto v2 = std::vector<unsigned char>(myVector.begin() , myVector.begin()+16);
     debug_print2("result: ",v2);

    //unsigned char result[BUFSIZ] = {myVector[0], myVector[1], myVector[2], myVector[3], myVector[4], myVector[5], myVector[6], myVector[7], '\0'};
    //std::cout << "result: " << result;

    double time_taken = double(end - start);
    std::cout << "pack time: " << std::fixed
              << time_taken << std::setprecision(5);
    std::cout << " sec " << std::endl;
    return 0;
}